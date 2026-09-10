# 1. fck-nat 최신 ARM64 AMI 조회
data "aws_ami" "fck_nat" {
  most_recent = true
  owners      = ["568608671756"]

  filter {
    name   = "name"
    values = ["fck-nat-al2023-hvm-*-arm64-ebs"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 2. NAT 인스턴스 전용 보안그룹
resource "aws_security_group" "nat" {
  name        = "${var.project_name}-${var.environment}-nat-sg"
  description = "Security Group for NAT Instances (Private Subnet egress traffic)"
  vpc_id      = var.vpc_id

  # VPC 내부 사설망(EKS/App)에서 오는 모든 아웃바운드 인터넷 요청 허용
  ingress {
    description = "Allow inbound traffic from VPC internal CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # 외부 인터넷으로 나가는 모든 트래픽 허용
  egress {
    description = "Allow all outbound traffic to internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-sg"
    }
  )
}

# 3. NAT 인스턴스 생성 (2AZ 각 1대)
resource "aws_instance" "nat" {
  count                  = length(var.public_subnet_ids)
  ami                    = data.aws_ami.fck_nat.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.nat.id]

  # NAT 인스턴스 핵심 설정: 자신 외의 트래픽을 중계할 수 있도록 비활성화
  source_dest_check = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
    }
  )
}

# 4. 각 NAT 인스턴스용 고정 공인 IP (Elastic IP) 할당
resource "aws_eip" "nat" {
  count    = length(var.public_subnet_ids)
  instance = aws_instance.nat[count.index].id
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
    }
  )
}

# 5. 프라이빗 라우팅 테이블에 0.0.0.0/0 -> 해당 AZ의 NAT 인스턴스 연결 (2AZ HA)
resource "aws_route" "private_nat" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[count.index].primary_network_interface_id
}
