variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "instance_type" {
  description = "EC2 인스턴스 사양"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH 접속용 EC2 키페어 이름 (없으면 null)"
  type        = string
  default     = null
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
