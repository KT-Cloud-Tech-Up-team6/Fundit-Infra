variable "external_secrets_chart_version" {
  description = "External Secrets Operator Helm 차트 버전"
  type        = string
  default     = "2.10.0"
}

variable "namespace" {
  description = "External Secrets Operator를 설치할 네임스페이스"
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "External Secrets Operator 컨트롤러 ServiceAccount 이름. IRSA 신뢰 정책의 sub와 일치해야 한다"
  type        = string
  default     = "external-secrets"
}

variable "secret_path_prefix" {
  description = "읽기를 허용할 Secrets Manager 이름과 Parameter Store 경로의 접두어"
  type        = string
  default     = "fundit/dev"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  # tfvars는 gitignore 대상이라 CI/CD apply는 항상 이 기본값을 쓴다
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}
