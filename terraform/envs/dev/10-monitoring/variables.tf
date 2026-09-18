variable "kube_prometheus_stack_chart_version" {
  description = "kube-prometheus-stack Helm 차트 버전"
  type        = string
  default     = "91.4.1"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
