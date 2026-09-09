module "ec2" {
  source = "../../../modules/ec2"

  project_name       = var.project_name
  environment        = var.environment
  ami_id             = data.aws_ami.dev_docker.id
  instance_type      = var.instance_type
  subnet_id          = data.terraform_remote_state.network.outputs.public_subnet_ids[0] # 퍼블릭 서브넷 1번에 배치
  security_group_ids = [module.security_groups.ec2_security_group_id]
  key_name           = var.key_name

  tags = var.common_tags
}
