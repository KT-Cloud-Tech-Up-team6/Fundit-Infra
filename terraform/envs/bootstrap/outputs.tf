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

output "terraform_ci_role_arn" {
  value       = aws_iam_role.terraform_ci.arn
  description = "GitHub Actions Terraform CI/CD 파이프라인이 사용할 IAM Role ARN"
}

output "github_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "GitHub Actions OIDC Provider ARN"
}
