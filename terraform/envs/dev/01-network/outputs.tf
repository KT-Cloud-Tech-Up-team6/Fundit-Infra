output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "EC2 배치를 위한 퍼블릭 서브넷 ID 목록"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.vpc.private_subnet_ids
}

# ----------------------------------------------------
# NAT 인스턴스 및 라우팅 출력값 추가
# ----------------------------------------------------
output "private_route_table_ids" {
  description = "프라이빗 라우팅 테이블 ID 목록 (AZ-A, AZ-B)"
  value       = module.vpc.private_route_table_ids
}

output "nat_public_ips" {
  description = "NAT 인스턴스 2대의 고정 공인 IP (EIP) 목록"
  value       = module.nat_instance.nat_public_ips
}

output "nat_instance_ids" {
  description = "생성된 NAT 인스턴스 ID 목록"
  value       = module.nat_instance.nat_instance_ids
}