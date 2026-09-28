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

# 인증서 검증 대기
# 동일 도메인(infrastudy.store 및 *.infrastudy.store)의 ACM DNS 검증 CNAME은 us-east-1과 ap-northeast-2에서 동일합니다.
# module.route53_acm에서 해당 CNAME의 Route53 레코드를 단일 소유자로 관리하므로,
# 중복 소유권 및 충돌을 방지하기 위해 module.route53_acm의 검증 레코드 FQDN을 직접 참조합니다.
resource "aws_acm_certificate_validation" "alb_seoul" {
  certificate_arn         = aws_acm_certificate.alb_seoul.arn
  validation_record_fqdns = module.route53_acm.validation_record_fqdns
}
