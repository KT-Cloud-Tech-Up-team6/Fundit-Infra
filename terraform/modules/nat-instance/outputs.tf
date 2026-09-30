output "nat_instance_ids" {
  description = "생성된 NAT 인스턴스 ID 목록 (ASG 전환으로 인해 동적 관리됨)"
  value       = []
}

output "nat_public_ips" {
  description = "NAT 인스턴스 고정 ENI에 할당된 고정 공인 IP (EIP) 목록"
  value       = aws_eip.nat[*].public_ip
}

output "nat_security_group_id" {
  description = "NAT 인스턴스 보안그룹 ID"
  value       = aws_security_group.nat.id
}

output "nat_primary_network_interface_ids" {
  description = "NAT 고정 Floating ENI ID 목록"
  value       = aws_network_interface.nat[*].id
}

output "nat_asg_names" {
  description = "NAT Auto Scaling Group 이름 목록"
  value       = aws_autoscaling_group.nat[*].name
}

output "nat_asg_arns" {
  description = "NAT Auto Scaling Group ARN 목록"
  value       = aws_autoscaling_group.nat[*].arn
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
  description = "NAT ASG CloudWatch Metric Alarm ARN 목록"
  value       = aws_cloudwatch_metric_alarm.nat_status[*].arn
}

output "failover_alert_sns_topic_arn" {
  description = "NAT 동시 장애 발생 시 긴급 알림을 발행하는 SNS 토픽 ARN (Slack/Discord/Email 등 연결용)"
  value       = aws_sns_topic.failover_alerts.arn
}
