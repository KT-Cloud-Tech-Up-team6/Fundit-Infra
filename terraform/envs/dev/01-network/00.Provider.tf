provider "aws" {
  region  = "ap-northeast-2"
  profile = "final"

  default_tags {
    tags = var.common_tags
  }
}
