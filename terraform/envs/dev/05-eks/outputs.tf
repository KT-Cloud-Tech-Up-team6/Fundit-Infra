output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트 URL"
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN"
  value       = module.eks.cluster_arn
}

output "cluster_security_group_id" {
  description = "EKS 클러스터 관리 보안 그룹 ID"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "EKS IRSA용 OIDC Provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS IRSA용 OIDC Provider URL"
  value       = module.eks.oidc_provider_url
}

output "system_node_group_id" {
  description = "시스템 노드 그룹 ID"
  value       = module.eks.system_node_group_id
}
