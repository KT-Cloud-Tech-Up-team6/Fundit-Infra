output "controller_role_arn" {
  description = "AWS Load Balancer Controller에 연결된 IAM Role ARN"
  value       = module.aws_load_balancer_controller.role_arn
}

output "controller_role_name" {
  description = "AWS Load Balancer Controller에 연결된 IAM Role Name"
  value       = module.aws_load_balancer_controller.role_name
}

output "helm_release_name" {
  description = "배포된 AWS Load Balancer Controller Helm 릴리스 이름"
  value       = helm_release.aws_load_balancer_controller.name
}

output "helm_release_version" {
  description = "배포된 AWS Load Balancer Controller Helm 차트 버전"
  value       = helm_release.aws_load_balancer_controller.version
}
