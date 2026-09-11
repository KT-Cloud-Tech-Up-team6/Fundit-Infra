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
