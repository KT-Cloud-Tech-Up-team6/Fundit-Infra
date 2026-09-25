variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ami_id" {
  description = "EC2에 사용할 AMI ID (Packer로 구운 AMI)"
  type        = string
}

variable "instance_type" {
  description = "인스턴스 유형"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "배치할 퍼블릭 서브넷 ID"
  type        = string
}

variable "security_group_ids" {
  description = "연결할 보안 그룹 ID 리스트"
  type        = list(string)
}

variable "key_name" {
  description = "SSH 접속용 EC2 키페어 이름 (선택 사항)"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "루트 볼륨 크기 (GB)"
  type        = number
  default     = 30
}

variable "iam_instance_profile" {
  description = "EC2 인스턴스에 연결할 IAM 인스턴스 프로파일 이름 (선택 사항)"
  type        = string
  default     = null
}

variable "http_endpoint" {
  description = "인스턴스 메타데이터 서비스(IMDS) 활성화 여부 (enabled 또는 disabled)"
  type        = string
  default     = "enabled"
}

variable "http_tokens" {
  description = "IMDSv2 토큰 필수 사용 여부 (optional 또는 required)"
  type        = string
  default     = "required"
}

variable "http_put_response_hop_limit" {
  description = "IMDS HTTP PUT 응답 홉 제한 (1~64)"
  type        = number
  default     = 1
}

variable "instance_metadata_tags" {
  description = "인스턴스 메타데이터에서 태그 접근 허용 여부 (enabled 또는 disabled)"
  type        = string
  default     = "disabled"
}

variable "tags" {
  type    = map(string)
  default = {}
}
