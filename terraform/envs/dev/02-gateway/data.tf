# 1. 03-compute 원격 상태에서 EC2 Public IP 조회
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/compute/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 2. 04-storage 원격 상태에서 미디어 S3 버킷 정보 조회 (이슈 #30)
data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/storage/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 3. 기존 Hosted Zone 조회 (신규 생성 아님, 이슈 #8)
data "aws_route53_zone" "existing" {
  name         = "${var.domain_name}."
  private_zone = false
}

# 4. EKS Ingress Controller가 프로비저닝한 ALB 조회
# [배포 순서 의존성 (Prerequisite)]
# 본 데이터 소스는 Terraform이 아닌 GitOps(EKS Ingress / AWS Load Balancer Controller)에 의해
# ALB가 먼저 생성되어 있어야 정상 동작합니다. 미생성 시 data 소스 조회 에러가 발생합니다.
data "aws_lb" "eks_alb" {
  tags = {
    "elbv2.k8s.aws/cluster" = "${var.project_name}-${var.environment}-eks"
    "ingress.k8s.aws/stack" = "${var.project_name}-alb"
  }
}
