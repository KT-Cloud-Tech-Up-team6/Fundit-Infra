variable "domain_name" {
  description = "ACM 인증서를 발급할 도메인 이름"
  type        = string
}

variable "subject_alternative_names" {
  description = "인증서에 추가로 포함할 대체 도메인 목록"
  type        = list(string)
  default     = []
}

variable "zone_id" {
  description = "DNS 검증 레코드를 추가할 기존 Route53 Hosted Zone ID"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
