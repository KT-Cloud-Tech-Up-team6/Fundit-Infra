# AI 하이라이트 생성 파이프라인 파드의 ServiceAccount가 assume하는 역할 (이슈 #115)
# IVS 자동 녹화 영상 S3 버킷(fundit-video-dev-team6)에 대한 읽기(GetObject, ListBucket) 권한을 안전하게 부여한다.
data "aws_iam_policy_document" "ai_s3_assume_role" {
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
      values   = ["system:serviceaccount:${var.ai_namespace}:${var.ai_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ai_s3" {
  name               = "fundit-dev-ai-s3-role"
  assume_role_policy = data.aws_iam_policy_document.ai_s3_assume_role.json
  tags               = var.common_tags
}

# IVS 자동 녹화 영상(VOD) S3 버킷 읽기 정책 (ListBucket / GetObject)
data "aws_iam_policy_document" "ai_s3" {
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      data.terraform_remote_state.storage.outputs.video_bucket_arn,
    ]
  }

  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${data.terraform_remote_state.storage.outputs.video_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "ai_s3" {
  name        = "fundit-dev-ai-s3-policy"
  description = "AI 하이라이트 생성 파이프라인의 VOD S3 버킷 읽기 전용 IAM 정책"
  policy      = data.aws_iam_policy_document.ai_s3.json
  tags        = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ai_s3" {
  role       = aws_iam_role.ai_s3.name
  policy_arn = aws_iam_policy.ai_s3.arn
}
