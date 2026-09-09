variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_id" {
  description = "보안 그룹이 속할 VPC ID"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "SSH 접속을 허용할 IP 대역"
  type        = list(string)
  default     = ["0.0.0.0/0"] 
}

variable "tags" {
  type    = map(string)
  default = {}
}
