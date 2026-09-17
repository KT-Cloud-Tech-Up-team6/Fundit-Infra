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
