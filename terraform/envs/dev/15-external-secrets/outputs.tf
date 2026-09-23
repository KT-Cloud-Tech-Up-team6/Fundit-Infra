output "external_secrets_role_arn" {
  description = "External Secrets Operator ServiceAccount에 연결된 IAM Role ARN"
  value       = aws_iam_role.external_secrets.arn
}

output "secret_path_prefix" {
  description = "Secrets Manager 이름과 Parameter Store 경로의 접두어. Fundit-GitOps의 ExternalSecret에서 이 접두어 아래 키를 참조한다"
  value       = var.secret_path_prefix
}
