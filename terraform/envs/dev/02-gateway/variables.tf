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

variable "domain_name" {
  description = "ACM 인증서를 발급할 도메인 이름 (기존 Route53 Hosted Zone)"
  type        = string
  default     = "infrastudy.store"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
