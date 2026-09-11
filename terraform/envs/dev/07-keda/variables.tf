variable "keda_chart_version" {
  description = "KEDA Helm 차트 버전"
  type        = string
  default     = "2.20.2"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
