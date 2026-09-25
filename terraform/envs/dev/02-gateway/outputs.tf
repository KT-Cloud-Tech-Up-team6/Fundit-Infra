output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID"
  value       = module.cloudfront.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront 도메인 주소"
  value       = module.cloudfront.cloudfront_domain_name
}

output "cloudfront_url" {
  description = "CloudFront 접속 전체 URL (HTTPS)"
  value       = "https://${module.cloudfront.cloudfront_domain_name}"
}

output "acm_certificate_arn" {
  description = "CloudFront/ALB에서 참조할 ACM 인증서 ARN (us-east-1)"
  value       = module.route53_acm.certificate_arn
}

output "waf_web_acl_arn" {
  description = "CloudFront에 연결된 WAF WebACL ARN"
  value       = module.waf.web_acl_arn
}

output "ivs_recording_configuration_arn" {
  description = "AWS IVS 자동 녹화 설정(Recording Configuration) ARN"
  value       = try(aws_ivs_recording_configuration.this[0].arn, null)
}
