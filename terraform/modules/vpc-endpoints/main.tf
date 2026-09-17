data "aws_region" "current" {}

# 1. Interface VPC 엔드포인트(ECR API, ECR DKR) 전용 보안그룹
resource "aws_security_group" "vpce" {
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "Security group for VPC Interface Endpoints (ECR API, ECR DKR)"
  vpc_id      = var.vpc_id
  # 인바운드 규칙은 최소 권한 원칙 및 계층 간 의존성 분리를 위해 모듈 내부에서 정의하지 않습니다.
  # 실제 소비자 계층(예: 05-eks)에서 aws_vpc_security_group_ingress_rule 리소스를 통해
  # EKS 클러스터 보안 그룹(cluster_security_group_id)으로부터의 443 접근을 허용합니다.

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-vpce-sg"
    }
  )
}

# 2. S3 Gateway VPC 엔드포인트 (비용 무료, 프라이빗 라우팅 테이블 연결)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-s3-vpce"
    }
  )
}

# 3. ECR API Interface VPC 엔드포인트 (인증/레포지토리 제어 API 통신)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-ecr-api-vpce"
    }
  )
}

# 4. ECR DKR Interface VPC 엔드포인트 (도커 이미지 레이어 다운로드 통신)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-ecr-dkr-vpce"
    }
  )
}
