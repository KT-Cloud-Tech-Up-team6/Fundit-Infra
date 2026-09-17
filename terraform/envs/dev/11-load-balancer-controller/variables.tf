variable "controller_chart_version" {
  description = "AWS Load Balancer Controller Helm 차트 버전"
  type        = string
  default     = "1.17.1"
}

variable "replica_count" {
  description = "AWS Load Balancer Controller 파드 복제본 수 (dev 환경은 리소스 절약을 위해 1개 권장)"
  type        = number
  default     = 1
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "Fundit"
    ManagedBy   = "Terraform"
    Layer       = "11-load-balancer-controller"
  }
}
