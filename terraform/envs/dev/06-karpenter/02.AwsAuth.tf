# aws-auth는 EKS가 클러스터 생성 시 자동으로 만드는 ConfigMap이라, 통째로 소유하는
# kubernetes_config_map 대신 data 필드만 관리하는 kubernetes_config_map_v1_data를 쓴다.
# Karpenter 노드 역할은 관리형 노드그룹과 달리 여기 등록해야 새 노드가 클러스터에 조인한다(이슈 #76).
# node-role/CI-role/관리자 계정은 이 레이어가 만드는 값이 아니라 지금 실제 aws-auth 값을 그대로 옮긴 것이다.
#
# force = true는 최초 apply 시 기존 필드 관리자(kubectl-client-side-apply, 어제 긴급조치로 등록됨)한테서
# 소유권을 가져오기 위해 필요하다. 이후로는 이 리소스가 data.mapRoles/mapUsers를 소유하므로,
# 누가 급하게 kubectl로 이 값을 또 고치면 다음 이 레이어 apply 때 코드 값으로 조용히 되돌아간다.
# 급한 조치가 다시 필요하면 이 파일도 같이 고쳐야 다음 apply에서 안 사라진다.
resource "kubernetes_config_map_v1_data" "aws_auth" {
  force = true

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::899957568205:role/fundit-dev-eks-node-role"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = module.karpenter.node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = "arn:aws:iam::899957568205:role/fundit-terraform-ci-role"
        username = "fundit-terraform-ci-role"
        groups   = ["system:masters"]
      },
    ])

    mapUsers = yamlencode([
      { userarn = "arn:aws:iam::899957568205:user/admin", username = "admin", groups = ["system:masters"] },
      { userarn = "arn:aws:iam::899957568205:user/infra_lsk", username = "infra_lsk", groups = ["system:masters"] },
      { userarn = "arn:aws:iam::899957568205:user/infra_hjy", username = "infra_hjy", groups = ["system:masters"] },
      { userarn = "arn:aws:iam::899957568205:user/infra_jyb", username = "infra_jyb", groups = ["system:masters"] },
      { userarn = "arn:aws:iam::899957568205:user/infra_lms", username = "infra_lms", groups = ["system:masters"] },
    ])
  }
}
