output "karpenter_controller_role_arn" {
  description = "Karpenter 컨트롤러 IAM Role ARN"
  value       = module.karpenter.controller_role_arn
}

output "karpenter_node_role_name" {
  description = "Karpenter가 만드는 노드용 IAM Role 이름 (EC2NodeClass.spec.role에 사용)"
  value       = module.karpenter.node_role_name
}
