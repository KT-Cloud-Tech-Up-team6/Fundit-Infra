module "route53_acm" {
  source = "../../../modules/route53-acm"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.existing.zone_id
  tags        = var.common_tags
}
