output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS 클러스터 제어부 API 엔드포인트 URL"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_certificate_authority_data" {
  description = "EKS 클러스터 CA 인증서 데이터"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS 클러스터 제어부가 자동 생성한 보안 그룹 ID"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "EKS IRSA용 OIDC 공급자 ARN"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "EKS IRSA용 OIDC 공급자 URL"
  value       = aws_iam_openid_connect_provider.this.url
}

output "node_role_arn" {
  description = "워커 노드 IAM 역할 ARN"
  value       = aws_iam_role.node.arn
}

output "system_node_group_id" {
  description = "시스템 노드 그룹 ID"
  value       = aws_eks_node_group.system.id
}
