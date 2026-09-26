variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

# 1. EC2 오리진 관련 변수
variable "app_origin_domain" {
  description = "웹/API 애플리케이션 원본 도메인 (현재: EC2, 추후: ALB)"
  type        = string
}

variable "app_origin_id" {
  description = "웹/API 오리진 식별자"
  type        = string
  default     = "app-origin"
}

variable "app_origin_protocol_policy" {
  description = "ALB 오리진 통신 프로토콜 정책 (http-only, https-only, match-viewer)"
  type        = string
  default     = "http-only"
}

# 2. S3 미디어 버킷 오리진 관련 변수
variable "media_origin_domain" {
  description = "S3 미디어 버킷의 도메인 주소"
  type        = string
}

variable "media_origin_id" {
  description = "S3 미디어 오리진 식별자"
  type        = string
  default     = "media-origin"
}

# 3. S3 비디오(VOD) 버킷 오리진 관련 변수
variable "video_origin_domain" {
  description = "S3 VOD 비디오 버킷의 도메인 주소 (선택 사항)"
  type        = string
  default     = null
}

variable "video_origin_id" {
  description = "S3 VOD 비디오 오리진 식별자"
  type        = string
  default     = "video-origin"
}


variable "tags" {
  type    = map(string)
  default = {}
}

variable "web_acl_id" {
  description = "연결할 WAF WebACL ARN (scope=CLOUDFRONT). 지정 안 하면 WAF 미연결"
  type        = string
  default     = null
}

variable "domain_name" {
  description = "CloudFront에 연결할 커스텀 도메인 이름 (예: infrastudy.store)"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "CloudFront에 적용할 us-east-1 ACM 인증서 ARN"
  type        = string
  default     = null
}
