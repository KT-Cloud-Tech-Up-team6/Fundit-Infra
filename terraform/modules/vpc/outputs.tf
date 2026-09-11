output "vpc_id" {
  description = "생성된 VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 리스트"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 리스트"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "데이터베이스 서브넷 ID 리스트"
  value       = aws_subnet.database[*].id
}

output "internet_gateway_id" {
  description = "인터넷 게이트웨이 ID"
  value       = aws_internet_gateway.main.id
}

# 프라이빗 라우팅 테이블 목록 추가 (NAT 인스턴스 연동용)
output "private_route_table_ids" {
  description = "프라이빗 라우팅 테이블 ID 리스트 (AZ별 분리)"
  value       = aws_route_table.private[*].id
}