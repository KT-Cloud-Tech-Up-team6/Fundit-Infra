variable "aws_region" {
  type        = string
  description = "배포할 AWS 리전"
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  type        = string
  description = "사용할 AWS CLI 프로필 이름"
}

variable "state_bucket_name" {
  type        = string
  description = "Terraform State를 저장할 S3 버킷 이름"
}

variable "common_tags" {
  type        = map(string)
  description = "공통 태그 목록"
  default     = {}
}
