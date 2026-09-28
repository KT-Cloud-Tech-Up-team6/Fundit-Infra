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

# 4. 각 NAT 인스턴스 전용 고정 공인 IP (Elastic IP) 할당
# fck-nat HA 모드에서는 실제 아웃바운드(POSTROUTING MASQUERADE)를 수행하는
# Primary ENI(eth0)에 부팅 시 fck-nat 서비스가 EIP를 동적으로 바인딩(associate-address)합니다.
# 따라서 테라폼에서는 보조 ENI에 묶지 않고 EIP 풀로 관리합니다.
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_ids)
  domain = "vpc"

  # fck-nat 런타임이 부팅 시 Primary ENI(eth0)에 EIP를 동적으로 바인딩(allow-reassociation)하므로
  # 테라폼과의 상태 경합(drift)을 방지합니다.
  lifecycle {
    ignore_changes = [network_interface, associate_with_private_ip, instance]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
    }
  )
}

# 5. 프라이빗 라우팅 테이블에 0.0.0.0/0 -> 해당 AZ의 고정 ENI 연결 (2AZ HA)
#
# [라우트 소유권 정책]
# network_interface_id는 Lambda Failover가 장애 시 반대 AZ ENI로 전환하므로
# Terraform이 drift를 감지해 원복(apply)하면 failover 효과가 즉시 취소됩니다.
# 따라서 runtime 라우트 타겟 변경은 Lambda가 소유하고,
# Terraform은 network_interface_id drift를 ignore합니다.
#
# [블랙홀 안전성 — ignore_changes가 블랙홀을 유발하지 않는 이유]
# 과거 주석에서 "ignore_changes = 블랙홀 감지 불가" 라고 기술했으나 이는 오해입니다.
# aws_network_interface.nat(고정 Floating ENI)는 Terraform이 관리하는 독립 리소스이며
# ASG 인스턴스가 교체되어도 ENI 자체는 삭제되지 않습니다.
# 따라서 정상 운영 중 ENI 블랙홀은 발생하지 않습니다.
# ENI가 실수로 수동 삭제된 극단적 케이스는 failover.py Reconciliation 로직이
# 인스턴스 running 이벤트 수신 시 라우트를 정상 ENI로 복구합니다.
#
# [01-network apply 운영 주의사항]
# failover 중(Lambda가 라우트를 반대 AZ ENI로 전환한 상태)에도
# apply는 network_interface_id를 건드리지 않아 egress가 유지됩니다.
# apply 전 라우트 현황 확인 권장:
#   aws ec2 describe-route-tables \
#     --route-table-ids <RTB_A_ID> <RTB_C_ID> \
#     --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'
resource "aws_route" "private_nat" {
  count                  = length(var.private_route_table_ids)
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.nat[count.index].id

  lifecycle {
    # Lambda Failover가 장애 시 라우트 타겟을 반대 AZ ENI로 전환하므로
    # Terraform의 원복 apply를 방지합니다. (라우트 소유권 정책 주석 참고)
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

  # fck-nat 공식 HA 아키텍처:
  # 1) eni_id: 프라이빗 라우팅 타깃인 고정 보조 ENI를 eth1(수신용)로 attach
  # 2) eip_id: 실제 인터넷 송신 인터페이스인 Primary ENI(eth0)에 고정 EIP를 associate
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

  # CloudWatch GroupInServiceInstances 지표 수집 활성화 (1분 단위)
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
  metrics_granularity = "1Minute"

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
