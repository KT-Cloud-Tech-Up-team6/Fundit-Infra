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

variable "loki_chart_version" {
  description = "Loki Helm 차트 버전"
  type        = string
  default     = "7.3.0"
}

variable "loki_storage_size" {
  description = "Loki 로그 청크 저장용 PVC 크기"
  type        = string
  default     = "20Gi"
}

variable "tempo_chart_version" {
  description = "Tempo Helm 차트 버전"
  type        = string
  default     = "1.24.4"
}

variable "tempo_storage_size" {
  description = "Tempo 트레이스 저장용 PVC 크기"
  type        = string
  default     = "15Gi"
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit Helm 차트 버전"
  type        = string
  default     = "0.58.2"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
