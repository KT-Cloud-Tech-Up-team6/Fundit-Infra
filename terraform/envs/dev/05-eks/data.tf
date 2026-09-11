# 01-network의 S3 상태 파일에서 VPC ID와 프라이빗 서브넷 ID를 자동으로 가져옴
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/network/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}
