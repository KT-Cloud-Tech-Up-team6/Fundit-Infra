terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Terraform tfstate 관리용 S3 bucket
module "tfstate_bucket" {
  source = "../../modules/s3"

  bucket_name       = var.state_bucket_name
  enable_versioning = true
  tags              = var.common_tags
}
