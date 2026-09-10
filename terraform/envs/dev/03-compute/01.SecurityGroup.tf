module "security_groups" {
  source = "../../../modules/security-groups"

  # 이미 Fundit-dev-app-ec2-sg로 적용되어 있다. name이 태그가 아니라 리소스 속성이라
  # var.project_name(소문자)을 그대로 쓰면 재생성된다. 고정값으로 분리한다.
  project_name = "Fundit"
  environment  = var.environment
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id

  tags = var.common_tags
}
