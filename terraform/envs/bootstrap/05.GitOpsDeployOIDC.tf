resource "aws_iam_role" "gitops_dev_deploy" {
  name                 = "fundit-dev-gitops-deploy-role"
  description          = "GitHub Actions Gateway deployment to the development EC2 instance"
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
          "token.actions.githubusercontent.com:sub" = "repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-GitOps@1359714048:environment:dev-deploy"
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "fundit-dev-gitops-deploy-role"
  })
}

resource "aws_ssm_document" "gitops_dev_deploy" {
  name            = "fundit-dev-deploy-gateway"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy a reviewed Fundit-GitOps main commit using the installed Gateway launcher"
    parameters = {
      GitCommit = {
        type              = "String"
        description       = "Full lowercase Git commit SHA from Fundit-GitOps main"
        allowedPattern    = "^[0-9a-f]{40}$"
        interpolationType = "ENV_VAR"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deployGateway"
      precondition = {
        StringEquals = ["platformType", "Linux"]
      }
      inputs = {
        timeoutSeconds = "1200"
        # 구형 Agent의 문자열 치환으로 우회하지 않고 ENV_VAR 미지원 시 배포를 중단한다.
        runCommand = [
          "set -eu",
          "test -n \"$${SSM_GitCommit:-}\" || exit 1",
          "exec runuser -u fundit-deploy -- /usr/local/libexec/fundit/deploy-dev-revision \"$SSM_GitCommit\""
        ]
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "fundit-dev-deploy-gateway"
  })
}

resource "aws_iam_role_policy" "gitops_dev_deploy" {
  name = "ssm-dev-deploy"
  role = aws_iam_role.gitops_dev_deploy.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunGatewayDocument"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = aws_ssm_document.gitops_dev_deploy.arn
      },
      {
        Sid      = "TargetDevelopmentApp"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        # 문서 ARN은 태그 조건을 만족하지 않으므로 인스턴스 권한과 분리한다.
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Name"    = "fundit-dev-app-ec2"
            "ssm:resourceTag/Project" = "Fundit"
          }
        }
      },
      {
        Sid    = "ReadCommandAndAgentStatus"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation"
        ]
        # 이 조회 API들은 개별 명령/인스턴스 ARN 제한을 지원하지 않는다.
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      }
    ]
  })
}
