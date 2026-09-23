variable "aws_region" {
  type        = string
  description = "배포할 AWS 리전"
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  type        = string
  description = "사용할 AWS CLI 프로필 이름"
  default     = "team6-infra"
}

variable "state_bucket_name" {
  type        = string
  description = "Terraform State를 저장할 S3 버킷 이름"
  default     = "fundit-tfstate-team6"
}

variable "common_tags" {
  type        = map(string)
  description = "공통 태그 목록"
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}

variable "ecr_repository_names" {
  type        = list(string)
  description = "생성할 ECR 리포지토리 이름 목록"
  default = [
    "fundit-backend", "fundit-frontend",
    "fundit-gateway", "fundit-auth", "fundit-member",
    "fundit-payment", "fundit-order", "fundit-funding",
    "fundit-project", "fundit-search", "fundit-fulfillment",
    "fundit-chat", "fundit-notification", "fundit-live",
    "fundit-ai-cuesheet", "fundit-ai-funding-story", "fundit-ai-copilot", "fundit-ai-highlight"
  ]
}

variable "github_repo" {
  type        = string
  description = "GitHub Actions CI/CD를 허용할 리포지토리 (org/repo 형식)"
  default     = "KT-Cloud-Tech-Up-team6/Fundit-Infra"
}
