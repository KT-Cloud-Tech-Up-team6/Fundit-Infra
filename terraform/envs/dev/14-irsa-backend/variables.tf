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

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
