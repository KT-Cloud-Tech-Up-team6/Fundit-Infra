output "bucket_id" {
  value       = local.bucket_id
  description = "생성된 S3 버킷 ID (이름)"
}

output "bucket_arn" {
  value       = local.bucket_arn
  description = "생성된 S3 버킷 ARN"
}

output "bucket_regional_domain_name" {
  value       = local.bucket_regional_domain_name
  description = "생성된 S3 버킷의 도메인 주소"
}