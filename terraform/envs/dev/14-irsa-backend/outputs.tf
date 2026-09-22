output "backend_s3_role_arn" {
  description = "백엔드 ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.backend_s3.arn
}
