output "state_bucket_name" {
  value       = module.tfstate_bucket.bucket_id
  description = "Terraform state 관리에 사용할 S3 버킷 이름"
}

output "state_bucket_arn" {
  value       = module.tfstate_bucket.bucket_arn
  description = "Terraform state 관리에 사용할 S3 버킷 ARN"
}

output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "생성된 ECR 저장소들의 전체 URL 목록"
}
# ----------------------------------------------------
# 미디어 버킷 출력값 추가 (Gateway 연동용)
# ----------------------------------------------------
output "media_dev_bucket_name" {
  value       = module.media_dev_bucket.bucket_id
  description = "dev 미디어 S3 버킷 이름"
}
output "media_dev_bucket_arn" {
  value       = module.media_dev_bucket.bucket_arn
  description = "dev 미디어 S3 버킷 ARN"
}
output "media_dev_bucket_regional_domain_name" {
  value       = module.media_dev_bucket.bucket_regional_domain_name
  description = "dev 미디어 S3 버킷 도메인 주소"
}