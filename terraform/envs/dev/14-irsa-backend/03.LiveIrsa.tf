# Live 서비스 파드의 ServiceAccount가 assume하는 역할.
# AWS IVS(Interactive Video Service) 및 IVS Chat API 호출 권한을 안전하게 부여한다.
data "aws_iam_policy_document" "live_ivs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(data.terraform_remote_state.eks.outputs.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${var.live_namespace}:${var.live_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(data.terraform_remote_state.eks.outputs.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "live_ivs" {
  name               = "fundit-${var.environment}-live-ivs-role"
  assume_role_policy = data.aws_iam_policy_document.live_ivs_assume_role.json
  tags               = var.common_tags
}

# Live 서비스가 AWS IVS 채널/스트림키/녹화설정 및 IVS Chat 룸/채팅토큰을 관리하기 위한 정책
data "aws_iam_policy_document" "live_ivs" {
  # 1. IVS 채널 및 스트림키 생성: dev 환경 태그 부여 강제 (aws:RequestTag)
  # AWS Service Authorization Reference에 따라 태그 포함 채널 생성 시 ivs:TagResource가 함께 요구됨
  statement {
    sid    = "AllowIVSResourceCreation"
    effect = "Allow"
    actions = [
      "ivs:CreateChannel",
      "ivs:CreateStreamKey",
      "ivs:TagResource",
    ]
    resources = [
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:channel/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream-key/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [var.environment]
    }
  }

  # 2. IVS 채널 및 스트림키 제어: dev 환경 태그가 부여된 리소스만 조작/삭제 가능 (aws:ResourceTag)
  statement {
    sid    = "AllowIVSResourceManagement"
    effect = "Allow"
    actions = [
      "ivs:GetChannel",
      "ivs:UpdateChannel",
      "ivs:DeleteChannel",
      "ivs:BatchGetChannel",
      "ivs:GetStreamKey",
      "ivs:DeleteStreamKey",
      "ivs:GetStream",
      "ivs:StopStream",
      "ivs:GetStreamSession",
      "ivs:ListStreamSessions",
      "ivs:UntagResource",
      "ivs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:channel/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream-key/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }

  # 3. IVS 녹화 설정 및 재생 키페어 읽기: 현재 계정 및 리전의 ARN 한정
  statement {
    sid    = "AllowIVSSharedReadOperations"
    effect = "Allow"
    actions = [
      "ivs:GetPlaybackKeyPair",
      "ivs:GetRecordingConfiguration",
    ]
    resources = [
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:playback-key/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:recording-configuration/*",
    ]
  }

  # 4. IVS Chat 룸 생성: dev 환경 태그 부여 강제 (aws:RequestTag)
  # AWS Service Authorization Reference에 따라 태그 포함 룸 생성 시 ivschat:TagResource가 함께 요구됨
  statement {
    sid    = "AllowIVSChatRoomCreation"
    effect = "Allow"
    actions = [
      "ivschat:CreateRoom",
      "ivschat:TagResource",
    ]
    resources = [
      "arn:aws:ivschat:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:room/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [var.environment]
    }
  }

  # 5. IVS Chat 룸 및 채팅토큰/이벤트 관리: dev 환경 태그가 부여된 Room만 제어 가능 (aws:ResourceTag)
  statement {
    sid    = "AllowIVSChatRoomManagement"
    effect = "Allow"
    actions = [
      "ivschat:GetRoom",
      "ivschat:UpdateRoom",
      "ivschat:DeleteRoom",
      "ivschat:CreateChatToken",
      "ivschat:SendEvent",
      "ivschat:DisconnectUser",
      "ivschat:DeleteMessage",
      "ivschat:UntagResource",
      "ivschat:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ivschat:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:room/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }
  }

  # 6. 안전 설계 (타 환경 태그 변조 및 권한 상승 방지):
  # 기존에 다른 환경(Environment != dev) 태그가 지정되어 있는 리소스에 대해 TagResource 호출을 명시적으로 차단하여,
  # 타 환경 리소스에 dev 태그를 붙여 관리 권한(ResourceTag/Environment)을 획득하는 우회 공격을 방지
  statement {
    sid    = "DenyTagExistingNonDevResources"
    effect = "Deny"
    actions = [
      "ivs:TagResource",
      "ivschat:TagResource",
    ]
    resources = [
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:channel/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream-key/*",
      "arn:aws:ivschat:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:room/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [var.environment]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Environment"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "live_ivs" {
  name        = "fundit-${var.environment}-live-ivs-policy"
  description = "Live 서비스 Pod의 AWS IVS 및 IVS Chat API 호출을 위한 IAM 정책"
  policy      = data.aws_iam_policy_document.live_ivs.json
  tags        = var.common_tags
}

resource "aws_iam_role_policy_attachment" "live_ivs" {
  role       = aws_iam_role.live_ivs.name
  policy_arn = aws_iam_policy.live_ivs.arn
}
