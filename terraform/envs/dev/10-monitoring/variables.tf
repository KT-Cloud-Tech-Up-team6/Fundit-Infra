variable "kube_prometheus_stack_chart_version" {
  description = "kube-prometheus-stack Helm 차트 버전"
  type        = string
  default     = "91.4.1"
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC 크기"
  type        = string
  default     = "10Gi"
}

variable "prometheus_retention_size" {
  description = "Prometheus TSDB 용량 기준 보존 상한(PVC 크기의 80% 권장)"
  type        = string
  default     = "8GB"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
