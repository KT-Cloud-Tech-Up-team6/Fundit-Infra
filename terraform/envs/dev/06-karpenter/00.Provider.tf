provider "aws" {
  region  = "ap-northeast-2"
  profile = "team6-infra"

  default_tags {
    tags = var.common_tags
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--profile", "team6-infra"]
    }
  }
}

# aws-auth ConfigMap 관리용(kubernetes_config_map_v1_data). helm 프로바이더의
# kubernetes{} 인증 블록과 값이 같다 — provider 타입이 달라 하나로 합칠 수 없으니,
# 인증 방식이 바뀌면(예: exec 명령 변경) 위 helm 블록도 같이 고쳐야 한다.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--profile", "team6-infra"]
  }
}
