# 1. 생성할 ECR 리포지토리 이름 목록 (예: ["fundit-backend", "fundit-frontend"])
variable "repository_names" {
  type        = list(string)
  description = "ECR 리포지토리 이름 목록"
}

# 2. 이미지 태그 덮어쓰기 허용 여부
# MUTABLE: 같은 태그(예: latest, dev)로 새 이미지를 덮어쓸 수 있음
# IMMUTABLE: 이미 존재하는 태그는 절대 덮어쓸 수 없음
variable "image_tag_mutability" {
  type        = string
  description = "이미지 태그 덮어쓰기 설정 (MUTABLE 또는 IMMUTABLE)"
  default     = "MUTABLE"
}

# 3. 이미지 푸시 시 보안 취약점 자동 검사 여부
variable "scan_on_push" {
  type        = bool
  description = "도커 이미지가 푸시될 때 CVE 보안 취약점을 자동으로 스캔할지 여부"
  default     = true
}

# 4. 보관할 최대 이미지 개수 (오래된 이미지 자동 삭제용)
variable "max_image_count" {
  type        = number
  description = "보관할 최대 도커 이미지 개수 (초과 시 오래된 것부터 자동 삭제)"
  default     = 10
}

# 5. 리소스 태그
variable "tags" {
  type        = map(string)
  description = "리소스에 부여할 태그"
  default     = {}
}

variable "max_commit_image_count" {
  type        = number
  description = "보관할 최대 도커 이미지 개수 (초과 시 오래된 것부터 자동 삭제)"
  default     = 10
}
