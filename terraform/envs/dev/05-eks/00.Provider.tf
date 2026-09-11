provider "aws" {
  region  = "ap-northeast-2"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}
