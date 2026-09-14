output "cnpg_backup_role_arn" {
  description = "PostgreSQL Cluster의 serviceAccountTemplate에 연결할 IAM Role ARN. Fundit-GitOps dev/cnpg/ 의 Cluster 리소스에서 참조한다"
  value       = module.cnpg.backup_role_arn
}
