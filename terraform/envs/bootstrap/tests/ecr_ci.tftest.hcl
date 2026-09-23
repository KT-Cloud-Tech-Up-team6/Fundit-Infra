# Mock만 사용해 기존 bootstrap의 실제 state, AWS API, 인증서 URL에 접근하지 않는다.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "1111111111111111111111111111111111111111" }]
    }
  }
}

override_resource {
  target = aws_iam_openid_connect_provider.github
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

override_module {
  target = module.tfstate_bucket
  outputs = {
    bucket_id  = "test-state"
    bucket_arn = "arn:aws:s3:::test-state"
  }
}

override_module {
  target = module.ecr
  outputs = {
    repository_arns = {
      fundit-backend          = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-backend"
      fundit-frontend         = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-frontend"
      fundit-order            = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-order"
      fundit-ai-cuesheet      = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-ai-cuesheet"
      fundit-ai-funding-story = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-ai-funding-story"
      fundit-ai-copilot       = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-ai-copilot"
      fundit-ai-highlight     = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-ai-highlight"
    }
    repository_urls = {
      fundit-backend  = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/fundit-backend"
      fundit-frontend = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/fundit-frontend"
    }
  }
}

run "trust_is_limited_to_verified_repository_branches" {
  # Terraform 1.10에서도 ARN을 검증하도록 mock 리소스만 생성한다. AWS apply가 아니다.
  command = apply

  assert {
    condition = alltrue([
      for role in aws_iam_role.ecr_ci :
      length(jsondecode(role.assume_role_policy).Statement) == 1 &&
      jsondecode(role.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(role.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(role.assume_role_policy).Statement[0].Principal == {
        Federated = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      } &&
      toset(keys(jsondecode(role.assume_role_policy).Statement[0].Condition)) == toset(["StringEquals"]) &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    ])
    error_message = "CI 인증은 기존 GitHub OIDC 공급자, WebIdentity, 정확한 aud/sub 조건으로만 허용해야 합니다."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.ecr_ci["backend"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-backend@1348212870:ref:refs/heads/develop" &&
      jsondecode(aws_iam_role.ecr_ci["frontend"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-FE@1344517410:ref:refs/heads/main" &&
      jsondecode(aws_iam_role.ecr_ci["ai_cuesheet"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-cuesheet@1375533793:ref:refs/heads/main" &&
      jsondecode(aws_iam_role.ecr_ci["ai_funding_story"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-AI-Funding-Story@1372645731:ref:refs/heads/main" &&
      jsondecode(aws_iam_role.ecr_ci["ai_copilot"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-copilot@1356653351:ref:refs/heads/main" &&
      jsondecode(aws_iam_role.ecr_ci["ai_highlight"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      "repo:KT-Cloud-Tech-Up-team6@316099892/Funddit-Ai-highlight@1363599970:ref:refs/heads/master"
    )
    error_message = "다른 저장소/ID, 임의 브랜치, PR, Environment subject로 신뢰 범위를 넓히면 안 됩니다."
  }
}

run "write_permissions_do_not_cross_repositories" {
  command = apply

  assert {
    condition = alltrue([
      for role in aws_iam_role.ecr_ci :
      role.tags["Project"] == "Fundit" &&
      role.tags["Team"] == "Team6" &&
      role.tags["ManagedBy"] == "Terraform"
    ])
    error_message = "CI Role은 bootstrap 기존 리소스와 같은 공통 태그를 유지해야 합니다."
  }

  assert {
    condition = (
      aws_iam_role_policy.ecr_ci_push["backend"].role == "fundit-backend-ci-role" &&
      aws_iam_role_policy.ecr_ci_push["frontend"].role == "fundit-frontend-ci-role" &&
      contains(jsondecode(aws_iam_role_policy.ecr_ci_push["backend"].policy).Statement[1].Resource, "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-backend") &&
      !contains(jsondecode(aws_iam_role_policy.ecr_ci_push["backend"].policy).Statement[1].Resource, "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-frontend") &&
      jsondecode(aws_iam_role_policy.ecr_ci_push["frontend"].policy).Statement[1].Resource == [
        "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-frontend"
      ]
    )
    error_message = "백엔드와 프론트엔드 Push 정책은 서로의 저장소 쓰기 권한을 침범하지 않아야 합니다."
  }

  assert {
    condition = (
      contains(jsondecode(aws_iam_role_policy.ecr_ci_push["backend"].policy).Statement[1].Resource, "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-order") &&
      alltrue([
        for key, repo in {
          ai_cuesheet      = "fundit-ai-cuesheet"
          ai_funding_story = "fundit-ai-funding-story"
          ai_copilot       = "fundit-ai-copilot"
          ai_highlight     = "fundit-ai-highlight"
        } :
        !contains(jsondecode(aws_iam_role_policy.ecr_ci_push["backend"].policy).Statement[1].Resource, "arn:aws:ecr:ap-northeast-2:123456789012:repository/${repo}") &&
        jsondecode(aws_iam_role_policy.ecr_ci_push[key].policy).Statement[1].Resource == [
          "arn:aws:ecr:ap-northeast-2:123456789012:repository/${repo}"
        ]
      ])
    )
    error_message = "AI 서비스 Push 정책은 자기 저장소 한 개만 허용하고, 백엔드 정책은 AI 저장소를 포함하지 않아야 합니다."
  }

  assert {
    condition = alltrue([
      for policy in aws_iam_role_policy.ecr_ci_push :
      length(jsondecode(policy.policy).Statement) == 2 &&
      jsondecode(policy.policy).Statement[0].Action == "ecr:GetAuthorizationToken" &&
      jsondecode(policy.policy).Statement[0].Resource == "*" &&
      alltrue([for statement in jsondecode(policy.policy).Statement : statement.Effect == "Allow"]) &&
      toset(jsondecode(policy.policy).Statement[1].Action) == toset([
        "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"
      ])
    ])
    error_message = "저장소 전체에 허용하는 작업은 로그인뿐이며, 이미지 작업은 Push에 필요한 권한으로 제한해야 합니다."
  }
}
