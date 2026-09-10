terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "fundit-tfstate-team6"
    key          = "dev/storage/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "team6-infra"
    use_lockfile = true
  }
}
