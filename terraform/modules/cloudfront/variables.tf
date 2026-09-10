variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

# 1. EC2 오리진 관련 변수
variable "app_origin_domain" {
  description = "웹/API 애플리케이션 원본 도메인 (현재: EC2, 추후: ALB)"
  type        = string
}

variable "app_origin_id" {
  description = "웹/API 오리진 식별자"
  type        = string
  default     = "app-origin"
}

# 2. S3 미디어 버킷 오리진 관련 변수
variable "media_origin_domain" {
  description = "S3 미디어 버킷의 도메인 주소"
  type        = string
}

variable "media_origin_id" {
  description = "S3 미디어 오리진 식별자"
  type        = string
  default     = "media-origin"
}

variable "tags" {
  type    = map(string)
  default = {}
}
