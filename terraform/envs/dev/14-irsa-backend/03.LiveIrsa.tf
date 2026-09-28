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
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.live_namespace}:${var.live_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.terraform_remote_state.eks.outputs.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "live_ivs" {
  name               = "FunditLiveIvsRole-${data.terraform_remote_state.eks.outputs.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.live_ivs_assume_role.json
  tags               = var.common_tags
}

# Live 서비스가 AWS IVS 채널/스트림키/녹화설정 및 IVS Chat 룸/채팅토큰을 관리하기 위한 정책
data "aws_iam_policy_document" "live_ivs" {
  # 1. IVS 목록 조회 작업: 리소스 레벨 권한을 지원하지 않는 API에 대해 wildcard 허용
  statement {
    sid    = "AllowIVSListOperations"
    effect = "Allow"
    actions = [
      "ivs:ListChannels",
      "ivs:ListStreamKeys",
      "ivs:ListPlaybackKeyPairs",
      "ivs:ListRecordingConfigurations",
    ]
    resources = ["*"]
  }

  # 2. IVS 채널, 스트림키, 녹화설정 제어: 현재 AWS 계정 및 리전의 리소스 ARN으로 한정
  statement {
    sid    = "AllowIVSResourceManagement"
    effect = "Allow"
    actions = [
      "ivs:CreateChannel",
      "ivs:GetChannel",
      "ivs:UpdateChannel",
      "ivs:DeleteChannel",
      "ivs:BatchGetChannel",
      "ivs:CreateStreamKey",
      "ivs:GetStreamKey",
      "ivs:DeleteStreamKey",
      "ivs:GetStream",
      "ivs:StopStream",
      "ivs:GetStreamSession",
      "ivs:ListStreamSessions",
      "ivs:GetPlaybackKeyPair",
      "ivs:GetRecordingConfiguration",
      "ivs:TagResource",
      "ivs:UntagResource",
      "ivs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:channel/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream-key/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:playback-key/*",
      "arn:aws:ivs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:recording-configuration/*",
    ]
  }

  # 3. IVS Chat 목록 조회 작업: 리소스 레벨 권한을 지원하지 않는 API에 대해 wildcard 허용
  statement {
    sid    = "AllowIVSChatListOperations"
    effect = "Allow"
    actions = [
      "ivschat:ListRooms",
      "ivschat:ListLoggingConfigurations",
    ]
    resources = ["*"]
  }

  # 4. IVS Chat 룸 및 채팅토큰/이벤트 관리: 현재 AWS 계정 및 리전의 Room ARN으로 한정
  statement {
    sid    = "AllowIVSChatRoomManagement"
    effect = "Allow"
    actions = [
      "ivschat:CreateRoom",
      "ivschat:GetRoom",
      "ivschat:UpdateRoom",
      "ivschat:DeleteRoom",
      "ivschat:CreateChatToken",
      "ivschat:SendEvent",
      "ivschat:DisconnectUser",
      "ivschat:DeleteMessage",
      "ivschat:TagResource",
      "ivschat:UntagResource",
      "ivschat:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ivschat:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:room/*",
    ]
  }
}

resource "aws_iam_policy" "live_ivs" {
  name        = "FunditLiveIvsPolicy-${data.terraform_remote_state.eks.outputs.cluster_name}"
  description = "Live 서비스 Pod의 AWS IVS 및 IVS Chat API 호출을 위한 IAM 정책"
  policy      = data.aws_iam_policy_document.live_ivs.json
  tags        = var.common_tags
}

resource "aws_iam_role_policy_attachment" "live_ivs" {
  role       = aws_iam_role.live_ivs.name
  policy_arn = aws_iam_policy.live_ivs.arn
}
