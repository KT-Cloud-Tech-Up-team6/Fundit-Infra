variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
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

