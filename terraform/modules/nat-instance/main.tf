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

# ----------------------------------------------------
# 3. 고가용성(HA) Floating ENI (사전 생성된 고정 네트워크 인터페이스)
# ASG로 인스턴스가 자동 교체(Self-Healing)되어도 프라이빗 라우팅 테이블과 EIP가
# 끊어지지 않도록 고정 ENI를 사전에 생성하여 관리합니다.
# ----------------------------------------------------
resource "aws_network_interface" "nat" {
  count             = length(var.public_subnet_ids)
  description       = "${var.project_name}-${var.environment}-nat-eni-${count.index + 1}"
  subnet_id         = var.public_subnet_ids[count.index]
  security_groups   = [aws_security_group.nat.id]
  source_dest_check = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-eni-${count.index + 1}"
    }
  )
}

# 4. 각 NAT 고정 ENI에 고정 공인 IP (Elastic IP) 연결
resource "aws_eip" "nat" {
  count             = length(var.public_subnet_ids)
  network_interface = aws_network_interface.nat[count.index].id
  domain            = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
    }
  )
}

# 5. 프라이빗 라우팅 테이블에 0.0.0.0/0 -> 해당 AZ의 고정 ENI 연결 (2AZ HA)
# 인스턴스가 종료되거나 새로 떠도 라우팅 테이블 타겟이 유지되어 블랙홀 방지
resource "aws_route" "private_nat" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.nat[count.index].id

  # Lambda에 의한 동적 페일오버/페일백 시 테라폼의 원복(drift) 방지
  lifecycle {
    ignore_changes = [network_interface_id]
  }
}

# ----------------------------------------------------
# 6. Auto Scaling Group용 Launch Template
# 최신 fck-nat ARM64 AMI 및 부팅 시 고정 ENI 자동 Attach 스크립트 적용
# ----------------------------------------------------
resource "aws_launch_template" "nat" {
  count       = length(var.public_subnet_ids)
  name_prefix = "${var.project_name}-${var.environment}-nat-${count.index + 1}-lt-"
  description = "Launch template for ${var.project_name} NAT instance ${count.index + 1} with ASG Self-Healing"

  image_id      = data.aws_ami.fck_nat.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.nat.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.nat.id]
    subnet_id                   = var.public_subnet_ids[count.index]
  }

  # 인스턴스 시작 시 fck-nat 서비스에 고정 ENI 및 EIP를 바인딩하도록 설정
  user_data = base64encode(<<-EOF
    #!/bin/sh
    echo "eni_id=${aws_network_interface.nat[count.index].id}" > /etc/fck-nat.conf
    echo "eip_id=${aws_eip.nat[count.index].id}" >> /etc/fck-nat.conf
    systemctl restart fck-nat || service fck-nat restart
  EOF
  )

  # IMDSv2 강제 적용 (보안 규정 준수)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      {
        Name      = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
        AutoSleep = "true"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------------
# 7. Auto Scaling Group (Self-Healing 단일 인스턴스 관리)
# 각 AZ(2a, 2c)마다 Min=1, Max=1, Desired=1의 ASG를 생성하여
# 인스턴스 비정상 상태 시 자동으로 종료하고 새 인스턴스를 프로비저닝
# ----------------------------------------------------
resource "aws_autoscaling_group" "nat" {
  count               = length(var.public_subnet_ids)
  name                = "${var.project_name}-${var.environment}-nat-asg-${count.index + 1}"
  vpc_zone_identifier = [var.public_subnet_ids[count.index]]

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  # EC2 Status Check 실패 시 자동 교체
  health_check_type         = "EC2"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.nat[count.index].id
    version = "$Latest"
  }

  # 새 인스턴스 롤아웃 시 이전 인스턴스에서 ENI 분리가 필요하므로 min_healthy_percentage = 0 설정
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
    propagate_at_launch = true
  }

  tag {
    key                 = "AutoSleep"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
