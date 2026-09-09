output "ec2_security_group_id" {
  description = "개발용 EC2 보안 그룹 ID"
  value       = aws_security_group.dev_ec2.id
}
