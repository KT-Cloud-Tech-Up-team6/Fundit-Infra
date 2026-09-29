variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "fundit"
}

variable "environment" {
  description = "배포 환경"
  type        = string
  default     = "dev"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}

variable "slack_webhook_secret_name" {
  description = "Slack Webhook URL을 저장한 AWS Secrets Manager 시크릿 이름 (키: webhook_url)"
  type        = string
  default     = "fundit/dev/slack-webhook"
}

variable "waf_web_acl_name" {
  description = "WAF WebACL 이름 (CloudWatch 차단 요청 알람 dimension 값)"
  type        = string
  default     = "fundit-dev-cloudfront-waf"
}

variable "cloudfront_5xx_threshold" {
  description = "CloudFront 5xx 에러율 알람 임계값 (%)"
  type        = number
  default     = 1
}

variable "alb_5xx_threshold" {
  description = "ALB 5xx 요청 수 알람 임계값 (count/분)"
  type        = number
  default     = 10
}

variable "nat_cpu_threshold" {
  description = "NAT 인스턴스 CPU 사용률 알람 임계값 (%)"
  type        = number
  default     = 80
}
