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
  # IVS 채널 및 스트림 제어
  statement {
    sid    = "AllowIVSManagement"
    effect = "Allow"
    actions = [
      "ivs:CreateChannel",
      "ivs:GetChannel",
      "ivs:ListChannels",
      "ivs:UpdateChannel",
      "ivs:DeleteChannel",
      "ivs:BatchGetChannel",
      "ivs:CreateStreamKey",
      "ivs:GetStreamKey",
      "ivs:ListStreamKeys",
      "ivs:DeleteStreamKey",
      "ivs:GetStream",
      "ivs:StopStream",
      "ivs:GetStreamSession",
      "ivs:ListStreamSessions",
      "ivs:GetPlaybackKeyPair",
      "ivs:ListPlaybackKeyPairs",
      "ivs:GetRecordingConfiguration",
      "ivs:ListRecordingConfigurations",
      "ivs:TagResource",
      "ivs:UntagResource",
      "ivs:ListTagsForResource",
    ]
    # IVS 채널과 IVS Chat 룸은 라이브 방송마다 동적으로 생성/삭제되어
    # 사전에 ARN을 특정할 수 없으므로 resource를 * 로 설정한다.
    # 향후 태그 기반(aws:ResourceTag/Project=Fundit) 조건 추가를 권장한다.
    resources = ["*"]
  }

  # IVS Chat 룸 및 토큰 발급/채팅 관리
  statement {
    sid    = "AllowIVSChatManagement"
    effect = "Allow"
    actions = [
      "ivschat:CreateRoom",
      "ivschat:GetRoom",
      "ivschat:ListRooms",
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
    # IVS 채널과 IVS Chat 룸은 라이브 방송마다 동적으로 생성/삭제되어
    # 사전에 ARN을 특정할 수 없으므로 resource를 * 로 설정한다.
    # 향후 태그 기반(aws:ResourceTag/Project=Fundit) 조건 추가를 권장한다.
    resources = ["*"]
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
