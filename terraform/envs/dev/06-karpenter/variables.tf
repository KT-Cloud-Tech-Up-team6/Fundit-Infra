variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
  default     = "1.14.0"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  # tfvars는 gitignore 대상이라 CI/CD apply는 항상 이 기본값을 쓴다.
  default = {
    Project     = "Fundit"
    Team        = "Team6"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

variable "security_transfer_bucket_name" {
  description = "Ansible 보안 점검 파일 전송용 S3 버킷 이름 (이슈 #114)"
  type        = string
  default     = "fundit-security-ansible-transfer-dev-team6"
}
