module "cloudfront" {
  source = "../../../modules/cloudfront"

  project_name        = var.project_name
  environment         = var.environment
  app_origin_domain   = data.aws_lb.eks_alb.dns_name
  media_origin_domain = data.terraform_remote_state.storage.outputs.media_bucket_regional_domain_name
  video_origin_domain = local.video_bucket_regional_domain
  web_acl_id          = module.waf.web_acl_arn
  domain_name         = var.domain_name
  acm_certificate_arn = module.route53_acm.certificate_arn
  tags                = var.common_tags
}


