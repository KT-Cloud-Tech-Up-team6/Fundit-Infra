variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "fundit"
}

variable "environment" {
  description = "배포 환경 (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "EKS 쿠버네티스 버전"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "EKS 클러스터가 위치할 VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "EKS 클러스터 제어부 ENI 및 워커 노드가 배치될 서브넷 ID 목록"
  type        = list(string)
}

variable "node_instance_types" {
  description = "시스템 노드 그룹의 EC2 인스턴스 유형 목록"
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

variable "tags" {
  description = "추가 리소스 태그"
  type        = map(string)
  default     = {}
}
