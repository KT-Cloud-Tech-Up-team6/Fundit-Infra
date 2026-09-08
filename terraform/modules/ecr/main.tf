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

# ==============================================================================
# 2. ECR 수명 주기 정책 (Lifecycle Policy)
#    - 릴리즈 태그(v*, release*): 규칙에 넣지 않아 영구 보존 (삭제 절대 안 됨!)
#    - 커밋/개발 태그(sha-*, dev-*, commit-*): 최신 10개만 유지하고 오래된 것 자동 삭제
#    - 태그 없는 찌꺼기 이미지: 1일 뒤 자동 삭제
# ==============================================================================
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [
      # 1순위: 빌드가 덮어씌워져 태그가 떨어진 불필요한 이미지는 1일 뒤 즉시 삭제
      {
        rulePriority = 1
        description  = "태그 없는 이미지는 1일 후 자동 삭제"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      # 2순위: 깃 커밋 및 개발용 임시 태그는 최신 10개만 보관하고 이전 것은 자동 청소
      {
        rulePriority = 2
        description  = "커밋 태그(sha-*, dev-*, commit-*)는 최신 10개만 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "dev-", "commit-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
