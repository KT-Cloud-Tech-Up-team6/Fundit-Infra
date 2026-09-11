# ====================================================
# 1. GitHub Actions OIDC 인증서 지문(Fingerprint) 자동 조회
# ====================================================
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ====================================================
# 2. GitHub Actions OIDC 공급자(Identity Provider) 등록
# ====================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = merge(
    var.common_tags,
    {
      Name = "github-actions-oidc-provider"
    }
  )
}

# ====================================================
# 3. Terraform CI/CD 전용 IAM Role
# ====================================================
resource "aws_iam_role" "terraform_ci" {
  name        = "fundit-terraform-ci-role"
  description = "GitHub Actions Terraform CI/CD 파이프라인 실행용 IAM Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # 우리 팀의 Fundit-Infra 리포지토리에서 온 요청만 승인
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"          }
          # STS를 수신자로 하는 토큰만 승인
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "fundit-terraform-ci-role"
    }
  )
}

# ====================================================
# 4. Terraform 실행에 필요한 관리자 권한 연결
# ====================================================
resource "aws_iam_role_policy_attachment" "terraform_ci_admin" {
  role       = aws_iam_role.terraform_ci.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
