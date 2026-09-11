output "controller_role_arn" {
  description = "Karpenter 컨트롤러가 assume하는 IAM Role ARN (ServiceAccount 연결용)"
  value       = aws_iam_role.controller.arn
}

output "node_role_arn" {
  description = "Karpenter가 만드는 노드에 붙는 IAM Role ARN"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Karpenter가 만드는 노드에 붙는 IAM Role 이름 (EC2NodeClass.spec.role에 사용)"
  value       = aws_iam_role.node.name
}
