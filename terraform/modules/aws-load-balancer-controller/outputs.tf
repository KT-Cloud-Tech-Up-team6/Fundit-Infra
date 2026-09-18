output "role_arn" {
  description = "AWS Load Balancer Controller에 연결할 IAM Role의 ARN"
  value       = aws_iam_role.controller.arn
}

output "role_name" {
  description = "AWS Load Balancer Controller에 연결할 IAM Role의 이름"
  value       = aws_iam_role.controller.name
}

output "policy_arn" {
  description = "AWS Load Balancer Controller에 부여된 IAM Policy의 ARN"
  value       = aws_iam_policy.controller.arn
}

output "service_account_name" {
  description = "AWS Load Balancer Controller가 사용할 ServiceAccount 이름"
  value       = var.service_account_name
}

output "namespace" {
  description = "AWS Load Balancer Controller가 배포될 네임스페이스"
  value       = var.namespace
}
