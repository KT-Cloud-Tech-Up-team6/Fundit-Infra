variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC 공급자 ARN (IRSA용)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC 공급자 URL (https:// 제외, IRSA용)"
  type        = string
}

variable "backup_bucket_name" {
  description = "CNPG 백업 대상 S3 버킷 이름"
  type        = string
}

variable "backup_namespace" {
  description = "PostgreSQL Cluster가 배포될 네임스페이스. GitOps에서 이 네임스페이스 안에 Cluster를 만들고 backup_role_arn을 serviceAccountTemplate에 연결한다"
  type        = string
}

variable "postgres_cluster_name" {
  description = "Fundit-GitOps에서 만들 PostgreSQL Cluster 리소스 이름. CNPG는 Cluster와 같은 이름으로 ServiceAccount를 자동 생성하므로, IAM 신뢰 정책의 sub 조건을 이 이름으로 정확히 고정한다. GitOps 쪽 Cluster 이름을 이 값과 다르게 만들면 IRSA가 동작하지 않는다"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
