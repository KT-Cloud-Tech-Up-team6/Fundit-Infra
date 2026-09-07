terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "fundit-tfstate-team6"          # 아까 만든 버킷 이름
    key          = "dev/network/terraform.tfstate" # 고유한 경로 지정!
    region       = "ap-northeast-2"
    profile      = "final"
    use_lockfile = true # S3 Native Lock 활성화!
  }
}
