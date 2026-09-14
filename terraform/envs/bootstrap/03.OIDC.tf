# ====================================================
# AWS 계정 및 파티션 정보 자동 조회
# ====================================================
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

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
  description = "IAM Role for GitHub Actions Terraform CI/CD pipeline"

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
          # PR 이벤트 및 main 브랜치 푸시/머지 이벤트만 허용 (임의 브랜치 차단)
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repo}:pull_request",
              "repo:${var.github_repo}:ref:refs/heads/main",
              "repo:KT-Cloud-Tech-Up-team6*/Fundit-Infra*:pull_request",
              "repo:KT-Cloud-Tech-Up-team6*/Fundit-Infra*:ref:refs/heads/main"
            ]
          }
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
# 4. Terraform 실행에 필요한 기본 권한 (PowerUserAccess)
# ====================================================
# PowerUserAccess: IAM을 제외한 모든 AWS 서비스에 대한 접근 권한 부여 (최소 권한 원칙)
resource "aws_iam_role_policy_attachment" "terraform_ci_poweruser" {
  role       = aws_iam_role.terraform_ci.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

# ====================================================
# 5. EKS 및 Karpenter 등 프로젝트 인프라 관리를 위한 전용 IAM 인라인 정책
# ====================================================
# PowerUserAccess는 iam:* 권한이 제외되어 있으므로, Terraform이 워커 노드 Role,
# 컨트롤러 Role, OIDC 프로바이더 등을 프로비저닝할 수 있도록 프로젝트 리소스 범위로 한정된 IAM 권한 부여
resource "aws_iam_role_policy" "terraform_ci_iam" {
  name = "fundit-terraform-ci-iam-permissions"
  role = aws_iam_role.terraform_ci.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1) IAM 리소스 조회/목록 (Terraform refresh 및 plan 필수)
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      },
      # 2) 프로젝트 전용 IAM Role 관리 (fundit-* 및 Karpenter*)
      {
        Sid    = "ManageProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/fundit-*",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/Karpenter*"
        ]
      },
      # 3) 프로젝트 전용 IAM Policy 관리 (fundit-* 및 Karpenter*)
      {
        Sid    = "ManageProjectPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/fundit-*",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/Karpenter*"
        ]
      },
      # 4) EKS 및 GitHub OIDC 공급자 관리
      {
        Sid    = "ManageOIDCProviders"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*"
      },
      # 5) Instance Profile 관리 (워커노드 및 Karpenter)
      {
        Sid    = "ManageInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/fundit-*",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/Karpenter*"
        ]
      },
      # 6) PassRole 권한 (EKS 및 EC2에 Role 위임)
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/fundit-*",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/Karpenter*"
        ]
      }
    ]
  })
}
