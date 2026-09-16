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

override_resource {
  target = aws_ssm_document.gitops_dev_deploy
  values = {
    arn = "arn:aws:ssm:ap-northeast-2:123456789012:document/fundit-dev-deploy-gateway"
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
      fundit-backend  = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-backend"
      fundit-frontend = "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-frontend"
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
      "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-FE@1344517410:ref:refs/heads/main"
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
      jsondecode(aws_iam_role_policy.ecr_ci_push["backend"].policy).Statement[1].Resource ==
      "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-backend" &&
      jsondecode(aws_iam_role_policy.ecr_ci_push["frontend"].policy).Statement[1].Resource ==
      "arn:aws:ecr:ap-northeast-2:123456789012:repository/fundit-frontend"
    )
    error_message = "각 Push 정책은 자기 Role과 ECR 저장소 한 개에만 연결되어야 합니다."
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

run "gitops_deployment_permissions_are_bounded" {
  command = apply

  assert {
    condition = (
      aws_iam_role.gitops_dev_deploy.name == "fundit-dev-gitops-deploy-role" &&
      length(jsondecode(aws_iam_role.gitops_dev_deploy.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.gitops_dev_deploy.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_iam_role.gitops_dev_deploy.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.gitops_dev_deploy.assume_role_policy).Statement[0].Principal == {
        Federated = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      } &&
      jsondecode(aws_iam_role.gitops_dev_deploy.assume_role_policy).Statement[0].Condition == {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-GitOps@1359714048:environment:dev-deploy"
        }
      }
    )
    error_message = "GitOps 배포 Role은 기존 OIDC 공급자와 정확한 immutable dev-deploy subject/aud만 신뢰해야 합니다."
  }

  assert {
    condition = (
      aws_iam_role_policy.gitops_dev_deploy.role == "fundit-dev-gitops-deploy-role" &&
      aws_iam_role_policy.gitops_dev_deploy.name == "ssm-dev-deploy" &&
      length(jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement) == 3 &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement : statement.Effect == "Allow"]) &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[0].Action == "ssm:SendCommand" &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[0].Resource ==
      "arn:aws:ssm:ap-northeast-2:123456789012:document/fundit-dev-deploy-gateway" &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[1].Action == "ssm:SendCommand" &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[1].Resource ==
      "arn:aws:ec2:ap-northeast-2:123456789012:instance/*" &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[1].Condition == {
        StringEquals = {
          "ssm:resourceTag/Name"    = "fundit-dev-app-ec2"
          "ssm:resourceTag/Project" = "Fundit"
        }
      }
    )
    error_message = "SSM 실행은 전용 문서와 Name/Project 두 태그가 모두 맞는 계정·리전 내 앱 EC2로 제한해야 합니다."
  }

  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[2].Action) == toset([
        "ssm:GetCommandInvocation", "ssm:DescribeInstanceInformation"
      ]) &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[2].Resource == "*" &&
      jsondecode(aws_iam_role_policy.gitops_dev_deploy.policy).Statement[2].Condition == {
        StringEquals = { "aws:RequestedRegion" = "ap-northeast-2" }
      } &&
      aws_iam_role.gitops_dev_deploy.tags["Project"] == "Fundit" &&
      aws_iam_role.gitops_dev_deploy.tags["Team"] == "Team6" &&
      aws_iam_role.gitops_dev_deploy.tags["ManagedBy"] == "Terraform"
    )
    error_message = "전역 Resource는 리전 제한된 SSM 상태 조회 2개만 허용하고 공통 태그를 유지해야 합니다."
  }
}

run "gitops_document_only_accepts_a_commit" {
  command = apply

  assert {
    condition = (
      aws_ssm_document.gitops_dev_deploy.name == "fundit-dev-deploy-gateway" &&
      aws_ssm_document.gitops_dev_deploy.document_type == "Command" &&
      aws_ssm_document.gitops_dev_deploy.document_format == "JSON" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).schemaVersion == "2.2" &&
      toset(keys(jsondecode(aws_ssm_document.gitops_dev_deploy.content).parameters)) == toset(["GitCommit"]) &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).parameters.GitCommit.type == "String" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).parameters.GitCommit.allowedPattern == "^[0-9a-f]{40}$" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).parameters.GitCommit.interpolationType == "ENV_VAR" &&
      !contains(keys(jsondecode(aws_ssm_document.gitops_dev_deploy.content).parameters.GitCommit), "default")
    )
    error_message = "문서는 기본값 없는 전체 Git SHA 하나만 받고 ENV_VAR로 전달해야 합니다. 임의 명령·URL·경로 인수를 추가하면 안 됩니다."
  }

  assert {
    condition = (
      length(jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps) == 1 &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps[0].action == "aws:runShellScript" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps[0].name == "deployGateway" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps[0].precondition == {
        StringEquals = ["platformType", "Linux"]
      } &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps[0].inputs.timeoutSeconds == "1200" &&
      jsondecode(aws_ssm_document.gitops_dev_deploy.content).mainSteps[0].inputs.runCommand == [
        "set -eu",
        "test -n \"$${SSM_GitCommit:-}\" || exit 1",
        "exec runuser -u fundit-deploy -- /usr/local/libexec/fundit/deploy-dev-revision \"$SSM_GitCommit\""
      ]
    )
    error_message = "SSM 문서는 ENV_VAR 미지원 시 중단하고 고정된 비로그인 배포 사용자로 설치된 launcher만 실행해야 합니다."
  }
}
