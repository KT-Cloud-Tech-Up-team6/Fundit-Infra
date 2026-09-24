variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "fundit"
}

variable "environment" {
  description = "배포 환경"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "EKS 쿠버네티스 버전"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "시스템 노드 인스턴스 유형"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "시스템 노드 그룹 기본 노드 수"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "시스템 노드 그룹 최소 노드 수"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "시스템 노드 그룹 최대 노드 수"
  type        = number
  default     = 4
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    Project   = "Fundit"
    Team      = "Team6"
    ManagedBy = "Terraform"
  }
}

# ====================================================
# Stateful 전용 노드그룹 변수 (이슈 #71)
# ====================================================
variable "enable_stateful_node_group" {
  description = "Stateful 전용 노드 그룹 생성 여부"
  type        = bool
  default     = true
}

variable "stateful_instance_types" {
  description = "Stateful 노드 인스턴스 유형 (t3a.large 권장, t3.large fallback)"
  type        = list(string)
  default     = ["t3a.large", "t3.large"]
}

variable "stateful_desired_size_per_az" {
  description = "AZ당 Stateful 노드 기본 수"
  type        = number
  default     = 1
}

variable "stateful_min_size_per_az" {
  description = "AZ당 Stateful 노드 최소 수"
  type        = number
  default     = 1
}

variable "stateful_max_size_per_az" {
  description = "AZ당 Stateful 노드 최대 수"
  type        = number
  default     = 2
}

variable "security_transfer_bucket_name" {
  description = "Ansible 보안 점검 파일 전송용 S3 버킷 이름 (이슈 #114)"
  type        = string
  default     = "fundit-security-ansible-transfer-dev-team6"
}
