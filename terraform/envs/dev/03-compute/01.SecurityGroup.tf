module "security_groups" {
  source = "../../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id

  tags = var.common_tags
}
