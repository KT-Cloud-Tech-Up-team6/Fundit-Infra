variable "backend_namespace" {
  description = "IRSA를 쓸 백엔드 파드가 배포될 네임스페이스"
  type        = string
  default     = "dev"
}

variable "backend_service_account_name" {
  description = "Fundit-GitOps에서 만들 ServiceAccount 이름. GitOps 쪽 이름과 반드시 일치해야 한다"
  type        = string
  default     = "fundit-backend-sa"
}

variable "ai_namespace" {
  description = "IRSA를 쓸 AI 파드가 배포될 네임스페이스"
  type        = string
  default     = "dev"
}

variable "ai_service_account_name" {
  description = "Fundit-GitOps에서 만들 AI ServiceAccount 이름. GitOps 쪽 이름과 반드시 일치해야 한다"
  type        = string
  default     = "fundit-ai-sa"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  # tfvars는 gitignore 대상이라 CI/CD apply는 항상 이 기본값을 쓴다.
  # 빈 맵으로 두면 CI가 만드는 리소스에 비용 태그가 하나도 안 붙는다.
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}
