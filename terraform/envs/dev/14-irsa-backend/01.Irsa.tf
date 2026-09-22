# 백엔드 파드의 ServiceAccount가 assume하는 역할.
# dev 네임스페이스는 ArgoCD AppProject의 namespaceResourceWhitelist가 전부 열려 있어
# 와일드카드를 쓰면 그 네임스페이스의 다른 워크로드도 이 Role을 assume할 수 있다.
data "aws_iam_policy_document" "backend_s3_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.backend_namespace}:${var.backend_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_s3" {
  name               = "FunditBackendS3Role-${data.terraform_remote_state.eks.outputs.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.backend_s3_assume_role.json
  tags               = var.common_tags
}

# 미디어·비디오 버킷 대상. 추후 새 버킷이 생기면 이 목록에 ARN을 추가한다
data "aws_iam_policy_document" "backend_s3" {
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      data.terraform_remote_state.storage.outputs.media_bucket_arn,
      data.terraform_remote_state.storage.outputs.video_bucket_arn,
    ]
  }

  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${data.terraform_remote_state.storage.outputs.media_bucket_arn}/*",
      "${data.terraform_remote_state.storage.outputs.video_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "backend_s3" {
  name   = "FunditBackendS3Policy-${data.terraform_remote_state.eks.outputs.cluster_name}"
  policy = data.aws_iam_policy_document.backend_s3.json
}

resource "aws_iam_role_policy_attachment" "backend_s3" {
  role       = aws_iam_role.backend_s3.name
  policy_arn = aws_iam_policy.backend_s3.arn
}
