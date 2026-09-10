variable "project_name" {
  type    = string
  default = "fundit"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "tags" {
  type    = map(string)
  default = {}
}
