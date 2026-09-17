variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS 클러스터 OIDC Provider ARN (IRSA 신뢰 관계 설정용)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS 클러스터 OIDC Provider URL (https:// 없는 호스트/경로 형식)"
  type        = string
}

variable "namespace" {
  description = "AWS Load Balancer Controller가 배포될 네임스페이스"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "AWS Load Balancer Controller의 ServiceAccount 이름"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "tags" {
  description = "리소스에 부여할 공통 태그"
  type        = map(string)
  default     = {}
}
