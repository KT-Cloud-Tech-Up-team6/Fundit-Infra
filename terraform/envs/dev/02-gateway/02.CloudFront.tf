module "cloudfront" {
  source = "../../../modules/cloudfront"

  project_name        = var.project_name
  environment         = var.environment
  app_origin_domain   = data.terraform_remote_state.compute.outputs.ec2_public_dns
  media_origin_domain = data.terraform_remote_state.bootstrap.outputs.media_dev_bucket_regional_domain_name
  web_acl_id          = module.waf.web_acl_arn
  tags                = var.common_tags
}
