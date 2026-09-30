# Fundit-GitOps main의 Frontend 이미지 검증 전용 Role.
# GitOps workflow는 ECR tag의 실제 digest만 조회하며 이미지를 push/pull하지 않는다.
resource "aws_iam_role" "gitops_frontend_ecr_read" {
  name                 = "fundit-gitops-frontend-ecr-read-role"
  description          = "GitOps Frontend image tag and digest verification"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # GitOps 저장소의 immutable OIDC subject와 main만 허용한다.
          "token.actions.githubusercontent.com:sub" = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-GitOps@1359714048:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "fundit-gitops-frontend-ecr-read-role"
  })
}

resource "aws_iam_role_policy" "gitops_frontend_ecr_read" {
  name = "ecr-describe-frontend-image"
  role = aws_iam_role.gitops_frontend_ecr_read.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DescribeFrontendImage"
      Effect   = "Allow"
      Action   = "ecr:DescribeImages"
      Resource = module.ecr.repository_arns["fundit-frontend"]
    }]
  })
}

# Fundit-GitOps main의 Backend·AI 이미지 digest 검증 전용 Role.
# Frontend Role과 분리해 이번 CD 범위의 ECR 조회만 허용한다.
resource "aws_iam_role" "gitops_be_ai_ecr_read" {
  name                 = "fundit-gitops-be-ai-ecr-read-role"
  description          = "GitOps Backend and AI image tag and digest verification"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-GitOps@1359714048:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "fundit-gitops-be-ai-ecr-read-role"
  })
}

resource "aws_iam_role_policy" "gitops_be_ai_ecr_read" {
  name = "ecr-describe-be-ai-images"
  role = aws_iam_role.gitops_be_ai_ecr_read.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DescribeBackendAndAiImages"
      Effect = "Allow"
      Action = "ecr:DescribeImages"
      Resource = [for name in [
        "fundit-backend",
        "fundit-ai-copilot",
        "fundit-ai-highlight",
        "fundit-ai-cuesheet",
        "fundit-ai-funding-story",
      ] : module.ecr.repository_arns[name]]
    }]
  })
}
