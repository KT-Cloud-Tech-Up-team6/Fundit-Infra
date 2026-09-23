output "ec2_instance_id" {
  description = "개발용 EC2 인스턴스 ID"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "개발용 EC2 고정 공인 IP (EIP)"
  value       = module.ec2.public_ip
}

output "ec2_public_dns" {
  description = "개발용 EC2 퍼블릭 DNS 도메인 (CloudFront 연동용)"
  value       = module.ec2.public_dns
}

output "ansible_inspector_role_arn" {
  description = "Ansible 점검 서버 IAM 역할 ARN"
  value       = aws_iam_role.ansible_inspector.arn
}

output "ansible_inspector_instance_profile_name" {
  description = "Ansible 점검 서버 IAM 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.ansible_inspector.name
}