output "instance_id" {
  description = "생성된 EC2 인스턴스 ID"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "EC2에 할당된 고정 공인 IP (EIP)"
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "EC2 퍼블릭 DNS 도메인"
  value       = aws_instance.app.public_dns
}