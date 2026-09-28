# Route53 A 레코드 (infrastudy.store -> CloudFront Alias 연결)
resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.cloudfront.cloudfront_domain_name
    zone_id                = module.cloudfront.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# Route53 A 레코드 (origin-dev.infrastudy.store -> EKS Ingress ALB Alias 연결, 이슈 #95)
# CloudFront가 ALB와 HTTPS로 통신할 때 도메인 불일치(502)를 방지하기 위한 전용 오리진 도메인
resource "aws_route53_record" "alb_origin" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = "origin-${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_alb.dns_name
    zone_id                = data.aws_lb.eks_alb.zone_id
    evaluate_target_health = true
  }
}
