# 01-network 원격 상태 — NAT 인스턴스 ID, SNS 토픽 ARN 조회
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/network/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 02-gateway 원격 상태 — CloudFront 배포 ID, ALB 태그 조회
data "terraform_remote_state" "gateway" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/gateway/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 04-storage 원격 상태 — S3 버킷 이름 조회
data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/storage/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# NAT Failover Lambda (01-network에서 생성) — 에러/시간 알람의 dimension 값 조회
data "aws_lambda_function" "nat_failover" {
  function_name = "${var.project_name}-${var.environment}-nat-failover"
}

# NAT Failover SNS 토픽 (01-network에서 생성) — Slack Lambda 구독 추가 대상
data "aws_sns_topic" "nat_failover_alerts" {
  name = "${var.project_name}-${var.environment}-nat-failover-alerts"
}

# EKS Ingress Controller가 프로비저닝한 ALB — ALB 알람 dimension 값 조회
# [Prerequisite] GitOps 배포 후 ALB가 생성되어 있어야 함
data "aws_lb" "eks_alb" {
  tags = {
    "elbv2.k8s.aws/cluster" = "${var.project_name}-${var.environment}-eks"
    "ingress.k8s.aws/stack" = "${var.project_name}-alb"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
