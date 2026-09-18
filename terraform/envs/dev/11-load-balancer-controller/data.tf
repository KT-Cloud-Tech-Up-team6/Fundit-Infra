# 05-eks의 S3 상태 파일에서 클러스터 정보 및 OIDC Provider 정보를 가져옴
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/eks/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# 01-network의 S3 상태 파일에서 VPC ID를 가져옴 (LBC가 타깃 서브넷 및 보안그룹을 찾을 때 필요)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "fundit-tfstate-team6"
    key     = "dev/network/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "team6-infra"
  }
}

# Helm 프로바이더 인증용 클러스터 정보 (엔드포인트, CA 인증서) 직접 조회
data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}
