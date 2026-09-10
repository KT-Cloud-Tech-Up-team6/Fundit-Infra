variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "fundit"
}

variable "environment" {
  description = "배포 환경 (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "NAT 인스턴스가 위치할 VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "NAT 인바운드를 허용할 VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_ids" {
  description = "NAT 인스턴스를 배치할 퍼블릭 서브넷 ID 목록 (2AZ HA 구성용)"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "0.0.0.0/0 기본 라우트를 추가할 프라이빗 라우팅 테이블 ID 목록"
  type        = list(string)
}

variable "instance_type" {
  description = "NAT 인스턴스 사양"
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default     = {}
}
