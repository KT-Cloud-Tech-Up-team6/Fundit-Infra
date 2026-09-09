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

variable "tags" {
  type    = map(string)
  default = {}
}
