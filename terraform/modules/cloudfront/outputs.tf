output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront 배포 ARN (S3 버킷 정책 연결용)"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront 도메인 주소"
  value       = aws_cloudfront_distribution.main.domain_name
}
