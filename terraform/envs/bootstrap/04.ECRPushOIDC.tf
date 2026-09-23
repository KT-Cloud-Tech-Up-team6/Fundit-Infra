locals {
  # GitHub OIDC API의 immutable subject를 사용한다(backend·frontend 2026-09-14, AI 2026-09-23 조회). 이름 뒤 ID도 정확히 일치해야 한다.
  # 키를 고정해 ECR ARN이 apply 시점에 결정되더라도 Role 수는 plan에서 결정되게 한다.
  ecr_ci_repositories = {
    backend = {
      ecr_repository = "fundit-backend"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-backend@1348212870:ref:refs/heads/develop"
    }
    frontend = {
      ecr_repository = "fundit-frontend"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-FE@1344517410:ref:refs/heads/main"
    }
    ai_cuesheet = {
      ecr_repository = "fundit-ai-cuesheet"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-cuesheet@1375533793:ref:refs/heads/main"
    }
    ai_funding_story = {
      ecr_repository = "fundit-ai-funding-story"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-AI-Funding-Story@1372645731:ref:refs/heads/main"
    }
    ai_copilot = {
      ecr_repository = "fundit-ai-copilot"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-copilot@1356653351:ref:refs/heads/main"
    }
    ai_highlight = {
      ecr_repository = "fundit-ai-highlight"
      subject        = "repo:KT-Cloud-Tech-Up-team6@316099892/Funddit-Ai-highlight@1363599970:ref:refs/heads/master"
    }
  }
}

resource "aws_iam_role" "ecr_ci" {
  for_each = local.ecr_ci_repositories

  name                 = "${each.value.ecr_repository}-ci-role"
  description          = "GitHub Actions image push to ${each.value.ecr_repository}"
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
          "token.actions.githubusercontent.com:sub" = each.value.subject
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${each.value.ecr_repository}-ci-role"
  })
}

resource "aws_iam_role_policy" "ecr_ci_push" {
  for_each = local.ecr_ci_repositories

  name = "ecr-push"
  role = aws_iam_role.ecr_ci[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRLogin"
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        # 이 API는 저장소 ARN으로 제한할 수 없다. 이미지 작업은 아래에서 Role별 저장소로 제한한다.
        Resource = "*"
      },
      {
        Sid    = "PushToOwnRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        # 백엔드는 서비스별 독립 ECR 저장소 전체로 푸시한다. 다른 CI Role이 소유한 저장소는 제외한다.
        Resource = each.key == "backend" ? sort([
          for repo, arn in module.ecr.repository_arns : arn
          if !contains([for key, ci in local.ecr_ci_repositories : ci.ecr_repository if key != "backend"], repo)
        ]) : [module.ecr.repository_arns[each.value.ecr_repository]]
      }
    ]
  })
}
