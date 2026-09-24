output "backend_s3_role_arn" {
  description = "백엔드 ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.backend_s3.arn
}

output "ai_s3_role_arn" {
  description = "AI ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.ai_s3.arn
}

output "ai_s3_role_name" {
  description = "AI ServiceAccount에 연결된 IAM Role 이름"
  value       = aws_iam_role.ai_s3.name
}
