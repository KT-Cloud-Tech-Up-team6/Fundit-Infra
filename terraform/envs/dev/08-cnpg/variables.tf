variable "cnpg_chart_version" {
  description = "CloudNativePG Helm 차트 버전"
  type        = string
  default     = "0.29.0"
}

variable "backup_namespace" {
  description = "PostgreSQL Cluster가 배포될 네임스페이스"
  type        = string
  default     = "dev"
}

variable "postgres_cluster_name" {
  description = "Fundit-GitOps에서 만들 PostgreSQL Cluster 리소스 이름. GitOps 쪽 Cluster 이름과 반드시 일치해야 한다"
  type        = string
  default     = "fundit-dev-postgres"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
