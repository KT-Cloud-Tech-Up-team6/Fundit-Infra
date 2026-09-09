output "ec2_instance_id" {
  description = "개발용 EC2 인스턴스 ID"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "개발용 EC2 고정 공인 IP (EIP)"
  value       = module.ec2.public_ip
}
