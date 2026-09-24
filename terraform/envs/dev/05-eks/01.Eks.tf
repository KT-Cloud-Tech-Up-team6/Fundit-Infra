module "eks" {
  source = "../../../modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_version     = var.cluster_version
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids          = data.terraform_remote_state.network.outputs.private_subnet_ids
  node_instance_types = var.node_instance_types
  desired_size        = var.desired_size
  min_size            = var.min_size
  max_size            = var.max_size

  # Stateful 전용 노드그룹 설정 (이슈 #71)
  enable_stateful_node_group   = var.enable_stateful_node_group
  stateful_instance_types      = var.stateful_instance_types
  stateful_desired_size_per_az = var.stateful_desired_size_per_az
  stateful_min_size_per_az     = var.stateful_min_size_per_az
  stateful_max_size_per_az     = var.stateful_max_size_per_az

  # Ansible 보안 점검 파일 전송용 S3 버킷 설정 (이슈 #114)
  security_transfer_bucket_name = var.security_transfer_bucket_name

  tags = var.common_tags
}

locals {
  # 01-network가 배포되어 remote state에 vpc_endpoint_security_group_id가 등록되었는지 확인
  # 미배포 상태에서는 null을 반환하여 Unsupported attribute 에러를 방지하고 가짜 ID 실행을 차단
  vpce_security_group_id = try(data.terraform_remote_state.network.outputs.vpc_endpoint_security_group_id, null)
}

# EKS 클러스터(노드)에서 VPC Endpoint(ECR 등)로 향하는 443 포트 허용
# 01-network가 Apply되어 원격 상태에 보안그룹 ID가 준비되었을 때만 실제 ID로 안전하게 생성
resource "aws_vpc_security_group_ingress_rule" "vpce_from_eks" {
  count = local.vpce_security_group_id != null ? 1 : 0

  security_group_id            = local.vpce_security_group_id
  referenced_security_group_id = module.eks.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow EKS cluster to access ECR VPC Endpoints"
}

