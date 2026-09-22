variable "bucket_name" {
  type        = string
  description = "생성할 s3 버킷 이름"
}

variable "enable_versioning" {
  type        = bool
  description = "버킷 버전 활성화 여부"
  default     = true
}

variable "prevent_destroy" {
  type        = bool
  description = "버킷 삭제 방지 여부"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "리소스 태그"
  default     = {}
}

variable "cors_rules" {
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  description = "S3 버킷 CORS 규칙 목록 (선택 사항)"
  default     = []
}

variable "lifecycle_rules" {
  type = list(object({
    id     = string
    status = string
    filter = optional(object({
      prefix = optional(string)
    }))
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })))
    expiration = optional(object({
      days = number
    }))
    abort_incomplete_multipart_upload = optional(object({
      days_after_initiation = number
    }))
  }))
  description = "S3 버킷 수명 주기 규칙 목록 (선택 사항)"
  default     = []
}

