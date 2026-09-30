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
