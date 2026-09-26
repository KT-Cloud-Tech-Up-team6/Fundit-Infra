# 서울 리전(ap-northeast-2) ACM 인증서 - EKS Ingress ALB용 (이슈 #95)
# CloudFront용(us-east-1)과 별개로, 서울 리전의 ALB에 부착할 SSL/TLS 인증서
resource "aws_acm_certificate" "alb_seoul" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-acm-alb-seoul"
    }
  )
}

# DNS 검증 레코드 (Route53)
# 동일한 도메인(infrastudy.store)이므로 기존 CNAME 레코드와 값이 동일하여 allow_overwrite로 안전하게 처리
resource "aws_route53_record" "seoul_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb_seoul.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.existing.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# 인증서 검증 대기
resource "aws_acm_certificate_validation" "alb_seoul" {
  certificate_arn         = aws_acm_certificate.alb_seoul.arn
  validation_record_fqdns = [for r in aws_route53_record.seoul_validation : r.fqdn]
}
