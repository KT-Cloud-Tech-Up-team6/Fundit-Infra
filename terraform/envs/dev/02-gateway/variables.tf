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

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
