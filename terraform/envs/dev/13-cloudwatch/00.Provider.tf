# 서울 리전 (기본) — NAT, ALB, S3, Lambda 알람
provider "aws" {
  region  = "ap-northeast-2"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}

# us-east-1 alias — CloudFront / WAF 메트릭은 이 리전에서만 제공됨
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}
