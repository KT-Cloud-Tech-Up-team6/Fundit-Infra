terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# 1. ACM 인증서 요청 (CloudFront가 참조하므로 us-east-1 고정)
resource "aws_acm_certificate" "this" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# 2. DNS 검증 레코드를 기존 Hosted Zone에 추가
# for_each 키(dvo.domain_name)는 var.domain_name·subject_alternative_names에서 그대로 나와 plan 시점에 이미 정해져 있다.
# 레코드 값(resource_record_name/value)만 apply 시점에 채워진다.
# AWS ACM DNS 검증에서 와일드카드 도메인(*.example.com)은 베이스 도메인(example.com)과 동일한 CNAME을 공유합니다.
# 베이스 도메인이 이미 인증서 도메인 목록에 존재하는 경우에만 중복 생성을 방지하기 위해 와일드카드를 제외합니다.
# 베이스 도메인이 없는 독립 와일드카드(예: *.dev.example.com 단독 신청)인 경우에는 검증 CNAME 레코드가 정상 생성됩니다.
locals {
  all_domains = distinct(concat([var.domain_name], var.subject_alternative_names))
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
      } if !(
      startswith(dvo.domain_name, "*.") &&
      contains(local.all_domains, trimprefix(dvo.domain_name, "*."))
    )
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# 3. 검증 완료 대기
resource "aws_acm_certificate_validation" "this" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
