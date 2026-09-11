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

# helm 프로바이더 인증용. 05-eks 출력값에는 CA 인증서가 없어서 클러스터 이름으로 직접 조회한다
data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}
