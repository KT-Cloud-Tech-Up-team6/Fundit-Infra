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

output "ecr_ci_role_arns" {
  value       = { for name, role in aws_iam_role.ecr_ci : name => role.arn }
  description = "애플리케이션 이미지 Push용 IAM Role ARN (backend/frontend)"
}

output "gitops_dev_deploy_role_arn" {
  value       = aws_iam_role.gitops_dev_deploy.arn
  description = "GitOps 개발 EC2 배포용 IAM Role ARN"
}

output "gitops_dev_deploy_document_name" {
  value       = aws_ssm_document.gitops_dev_deploy.name
  description = "Gateway 배포 전용 SSM Command 문서 이름"
}

output "gitops_dev_deploy_document_version" {
  value       = aws_ssm_document.gitops_dev_deploy.latest_version
  description = "검토 후 GitOps Environment에 설정할 SSM 문서 버전"
}
