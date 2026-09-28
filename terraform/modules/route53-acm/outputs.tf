output "certificate_arn" {
  description = "검증 완료된 ACM 인증서 ARN (CloudFront/ALB에서 참조)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "validation_record_fqdns" {
  description = "Route53 ACM DNS 검증 레코드 FQDN 목록"
  value       = [for r in aws_route53_record.validation : r.fqdn]
}
