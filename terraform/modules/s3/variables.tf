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
