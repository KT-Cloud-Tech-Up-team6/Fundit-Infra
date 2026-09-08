output "repository_urls" {
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
  description = "생성된 각 ECR 저장소의 도커 푸시 URL"
}

output "repository_arns" {
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
  description = "생성된 각 ECR 저장소의 ARN"
}
