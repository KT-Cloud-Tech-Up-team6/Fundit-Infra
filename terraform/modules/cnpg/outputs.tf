output "backup_role_arn" {
  description = "PostgreSQL Cluster의 serviceAccountTemplate에 연결할 IAM Role ARN"
  value       = aws_iam_role.backup.arn
}
