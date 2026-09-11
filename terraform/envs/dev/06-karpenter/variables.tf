variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
  default     = "1.14.0"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
