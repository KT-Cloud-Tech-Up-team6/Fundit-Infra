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
  default     = {}
}
