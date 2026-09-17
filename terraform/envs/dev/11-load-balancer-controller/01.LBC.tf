# AWS Load Balancer Controller에 필요한 IAM Role 및 Policy (IRSA) 생성
module "aws_load_balancer_controller" {
  source = "../../../modules/aws-load-balancer-controller"

  cluster_name      = data.terraform_remote_state.eks.outputs.cluster_name
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.eks.outputs.oidc_provider_url

  tags = var.common_tags
}

# AWS Load Balancer Controller Helm 차트 배포
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.controller_chart_version

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.eks.outputs.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = module.aws_load_balancer_controller.service_account_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller.role_arn
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.network.outputs.vpc_id
  }

  set {
    name  = "replicaCount"
    value = tostring(var.replica_count)
  }

  set {
    name  = "ingressClass"
    value = "alb"
  }

  set {
    name  = "createIngressClassResource"
    value = "true"
  }
}
