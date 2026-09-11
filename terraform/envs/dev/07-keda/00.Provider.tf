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
