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

  tags = var.common_tags
}

# EKS 클러스터(노드)에서 VPC Endpoint(ECR 등)로 향하는 443 포트 허용
resource "aws_vpc_security_group_ingress_rule" "vpce_from_eks" {
  security_group_id            = data.terraform_remote_state.network.outputs.vpc_endpoint_security_group_id
  referenced_security_group_id = module.eks.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow EKS cluster to access ECR VPC Endpoints"
}
