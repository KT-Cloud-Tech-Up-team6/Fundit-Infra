variable "argocd_chart_version" {
  description = "ArgoCD Helm 차트 버전"
  type        = string
  default     = "10.9.1"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
