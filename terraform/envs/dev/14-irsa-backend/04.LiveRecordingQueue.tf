# ==============================================================================
# AWS IVS 녹화 완료(Recording End) 이벤트 수신용 SQS 및 EventBridge 파이프라인
# Live 서비스가 EventBridge로부터 IVS 녹화 종료 이벤트를 안전하게 전달받아
# VOD 다시보기 상태 갱신 및 CloudFront 재생 메타데이터를 저장하기 위한 인프라
# ==============================================================================

# 1. Dead Letter Queue (DLQ)
# Live 서비스 장애 또는 메시지 파싱 실패 시 유실 방지 (14일 보존)
resource "aws_sqs_queue" "live_recording_dlq" {
  name                      = "fundit-${var.environment}-live-recording-dlq"
  message_retention_seconds = 1209600 # 14일
  sqs_managed_sse_enabled   = true

  tags = var.common_tags
}

# 2. Main SQS Queue
# IVS 녹화 완료 이벤트를 수신하는 메인 큐
resource "aws_sqs_queue" "live_recording" {
  name                       = "fundit-${var.environment}-live-recording-queue"
  message_retention_seconds  = 86400 # 1일 (24시간)
  visibility_timeout_seconds = 60    # 백엔드(live-service) 처리 여유 시간 고려
  receive_wait_time_seconds  = 20    # Long Polling 활성화로 API 비용 절감 및 지연 단축
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.live_recording_dlq.arn
    maxReceiveCount     = 5
  })

  tags = var.common_tags
}

# 3. SQS Queue Policy
# EventBridge 서비스(events.amazonaws.com)가 메인 큐로 이벤트를 발행할 수 있도록 허용
# TLS 미암호화 연결 차단(DenyHTTP) 및 지정된 EventBridge Rule ARN에 한정 허용
data "aws_iam_policy_document" "live_recording_queue" {
  statement {
    sid       = "AllowEventBridgeSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.live_recording.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.live_recording.arn]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.live_recording.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "live_recording" {
  queue_url = aws_sqs_queue.live_recording.id
  policy    = data.aws_iam_policy_document.live_recording_queue.json
}

# DLQ에 대한 전송 암호화 강제 정책
data "aws_iam_policy_document" "live_recording_dlq" {
  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.live_recording_dlq.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "live_recording_dlq" {
  queue_url = aws_sqs_queue.live_recording_dlq.id
  policy    = data.aws_iam_policy_document.live_recording_dlq.json
}

# 4. EventBridge Rule (CloudWatch Event Rule)
# AWS IVS의 'IVS Recording State Change' 이벤트 중 'Recording End' 상태만 감지
resource "aws_cloudwatch_event_rule" "live_recording" {
  name        = "fundit-${var.environment}-ivs-recording-end"
  description = "AWS IVS 실시간 방송 녹화 완료(Recording End) 이벤트 수신"

  event_pattern = jsonencode({
    source        = ["aws.ivs"]
    "detail-type" = ["IVS Recording State Change"]
    detail = {
      recording_status = ["Recording End"]
    }
  })

  tags = var.common_tags
}

# 5. EventBridge Target
# 감지된 녹화 완료 이벤트를 Live 녹화 SQS 큐로 전달
resource "aws_cloudwatch_event_target" "live_recording" {
  rule      = aws_cloudwatch_event_rule.live_recording.name
  target_id = "SendToLiveRecordingSQS"
  arn       = aws_sqs_queue.live_recording.arn
}
