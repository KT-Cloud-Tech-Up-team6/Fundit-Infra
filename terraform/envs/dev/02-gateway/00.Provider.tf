provider "aws" {
  region  = "ap-northeast-2"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}

# CloudFront용 ACM 인증서는 us-east-1에서만 발급 가능
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}
