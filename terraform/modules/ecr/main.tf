# ==============================================================================
# 1. ECR 리포지토리 생성 블록
#    for_each를 사용하여 repository_names 목록에 적힌 개수만큼 반복 생성합니다.
# ==============================================================================
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  # 리포지토리 이름 (예: fundit-backend)
  name = each.value

  # 태그 덮어쓰기 허용 정책 (MUTABLE / IMMUTABLE)
  image_tag_mutability = var.image_tag_mutability

  # 도커 이미지 안에 보안 취약점(악성코드, 패키지 취약점)이 있는지 자동 검사
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # AWS KMS 기반 기본 암호화 (저장된 이미지 데이터 보호)
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# 수명 주기 정책(Lifecycle Policy) 제거:
# 단일 ECR(fundit-backend) 내 여러 마이크로서비스 이미지 공존 시 10개 제한에 따른 이미지 증발 방지
