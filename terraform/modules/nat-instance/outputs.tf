output "nat_instance_ids" {
  description = "생성된 NAT 인스턴스 ID 목록"
  value       = aws_instance.nat[*].id
}

output "nat_public_ips" {
  description = "NAT 인스턴스에 할당된 고정 공인 IP (EIP) 목록"
  value       = aws_eip.nat[*].public_ip
}

output "nat_security_group_id" {
  description = "NAT 인스턴스 보안그룹 ID"
  value       = aws_security_group.nat.id
}

output "nat_primary_network_interface_ids" {
  description = "NAT 인스턴스의 Primary ENI ID 목록"
  value       = aws_instance.nat[*].primary_network_interface_id
}

output "failover_lambda_arn" {
  description = "NAT Failover 처리 Lambda 함수 ARN"
  value       = aws_lambda_function.failover.arn
}

output "failover_lambda_function_name" {
  description = "NAT Failover 처리 Lambda 함수 이름"
  value       = aws_lambda_function.failover.function_name
}

output "nat_cloudwatch_alarm_arns" {
  description = "NAT 인스턴스 CloudWatch Metric Alarm ARN 목록"
  value       = aws_cloudwatch_metric_alarm.nat_status[*].arn
}
