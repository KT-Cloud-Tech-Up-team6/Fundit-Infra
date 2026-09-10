module "waf" {
  source = "../../../modules/waf"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  tags         = var.common_tags
}
