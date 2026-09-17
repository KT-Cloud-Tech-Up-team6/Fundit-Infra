output "s3_vpc_endpoint_id" {
  description = "S3 Gateway VPC 엔드포인트 ID"
  value       = aws_vpc_endpoint.s3.id
}

output "ecr_api_vpc_endpoint_id" {
  description = "ECR API Interface VPC 엔드포인트 ID"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "ecr_dkr_vpc_endpoint_id" {
  description = "ECR DKR Interface VPC 엔드포인트 ID"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_security_group_id" {
  description = "VPC 엔드포인트용 보안그룹 ID"
  value       = aws_security_group.vpce.id
}
