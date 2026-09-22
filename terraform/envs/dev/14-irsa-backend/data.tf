# 05-eks의 S3 상태 파일에서 클러스터 이름과 OIDC Provider 정보를 가져옴
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/eks/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 04-storage의 S3 상태 파일에서 미디어·비디오 버킷 ARN을 가져옴
data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/storage/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}
