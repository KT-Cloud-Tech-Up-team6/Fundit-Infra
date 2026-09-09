# 1. 01-network의 S3 상태 파일에서 VPC ID와 서브넷 ID를 자동으로 가져옴
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/network/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "final"
  }
}

# Packer로 구운 AMI 사용
data "aws_ami" "dev_docker" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["fundit-dev-docker-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
