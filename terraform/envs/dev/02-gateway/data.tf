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

# 2. bootstrap 원격 상태에서 미디어 S3 버킷 정보 조회
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "bootstrap/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 3. 기존 Hosted Zone 조회 (신규 생성 아님, 이슈 #8)
data "aws_route53_zone" "existing" {
  name         = "${var.domain_name}."
  private_zone = false
}
