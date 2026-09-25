variable "cluster_name" {
  description = "Karpenter가 노드를 붙일 EKS 클러스터 이름"
  type        = string
}

variable "oidc_provider_arn" {
  description = "클러스터 OIDC Provider ARN (IRSA 신뢰 정책용)"
  type        = string
}

variable "oidc_provider_url" {
  description = "클러스터 OIDC Provider URL (https:// 없이 호스트+경로만, AWS IAM이 저장하는 형식 그대로)"
  type        = string
}

variable "karpenter_namespace" {
  description = "Karpenter 컨트롤러가 배포될 네임스페이스"
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account_name" {
  description = "Karpenter 컨트롤러 ServiceAccount 이름"
  type        = string
  default     = "karpenter"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

variable "security_transfer_bucket_name" {
  description = "Ansible 보안 점검 파일 전송용 S3 버킷 이름 (지정 시 노드 Role에 S3 접근 정책 생성, 미지정 시 null)"
  type        = string
  default     = null
}
