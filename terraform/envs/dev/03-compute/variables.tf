variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "instance_type" {
  description = "EC2 인스턴스 사양"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH 접속용 EC2 키페어 이름 (없으면 null)"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  # tfvars는 gitignore 대상이라 CI/CD apply는 항상 이 기본값을 쓴다.
  # 빈 맵으로 두면 CI가 만드는 리소스에 비용 태그가 하나도 안 붙거나 삭제된다.
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}
