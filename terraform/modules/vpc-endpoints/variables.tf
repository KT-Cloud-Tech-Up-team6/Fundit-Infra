variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "fundit"
}

variable "environment" {
  description = "배포 환경 (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록 (보안그룹 인바운드 허용용)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Interface 엔드포인트(ENI)를 배치할 프라이빗 서브넷 ID 목록"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "S3 Gateway 엔드포인트를 연결할 프라이빗 라우팅 테이블 ID 목록"
  type        = list(string)
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
