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
