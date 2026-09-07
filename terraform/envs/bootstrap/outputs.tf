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
