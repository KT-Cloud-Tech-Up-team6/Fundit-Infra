# ──────────────────────────────────────────────────────────────────────────────
# S3 알람 — media 버킷 (이미지/영상 업로드), video 버킷
#
# [주의] S3 메트릭 유형에 따라 활성화 방법이 다름:
#   - BucketSizeBytes / NumberOfObjects: 기본 제공, period 반드시 86400(1일) 이상
#   - AllRequests / 4xxErrors 등 요청 지표: 각 버킷에 "요청 지표(Request Metrics)" 활성화 필요
#     S3 콘솔 > 버킷 선택 > 지표 탭 > 요청 지표 구성 또는 Terraform aws_s3_bucket_metric 리소스 사용
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # 04-storage 원격 상태에서 버킷 이름 안전 참조
  media_bucket_name = try(data.terraform_remote_state.storage.outputs.media_bucket_name, null)
  video_bucket_name = try(data.terraform_remote_state.storage.outputs.video_bucket_name, null)
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 요청 지표 활성화 (Request Metrics 필터)
# 이 리소스가 있어야 4xx / AllRequests 지표가 CloudWatch에 나타남
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_metric" "media_all" {
  count  = local.media_bucket_name != null ? 1 : 0
  bucket = local.media_bucket_name
  name   = "EntireBucket"
}

resource "aws_s3_bucket_metric" "video_all" {
  count  = local.video_bucket_name != null ? 1 : 0
  bucket = local.video_bucket_name
  name   = "EntireBucket"
}

# ──────────────────────────────────────────────────────────────────────────────
# media 버킷 4xx 에러율 알람 (업로드 실패 탐지)
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "media_bucket_4xx" {
  count = local.media_bucket_name != null ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-s3-media-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  # 4xx 에러율 = 4xxErrors / AllRequests * 100 (Metric Math 대신 단순 임계 사용)
  metric_name        = "4xxErrors"
  namespace          = "AWS/S3"
  period             = 300
  statistic          = "Sum"
  threshold          = 50 # 5분 내 50건 이상 4xx
  alarm_description  = "media 버킷에서 5분 내 50건 이상의 4xx 오류가 발생했습니다. 클라이언트 인증/권한 문제 또는 잘못된 요청을 확인하세요."
  treat_missing_data = "notBreaching"

  dimensions = {
    BucketName = local.media_bucket_name
    FilterId   = "EntireBucket"
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-s3-media-4xx-errors"
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# media 버킷 용량 급증 알람
# BucketSizeBytes: period 반드시 86400(하루) — 일 1회 수집
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "media_bucket_size" {
  count = local.media_bucket_name != null ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-s3-media-size-large"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400 # 1일 단위 메트릭
  statistic           = "Average"
  threshold           = 10737418240 # 10GiB = 10 * 1024^3
  alarm_description   = "media 버킷 총 용량이 10GiB를 초과했습니다. S3 비용 급증 위험이 있습니다."
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = local.media_bucket_name
    StorageType = "StandardStorage"
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-s3-media-size-large"
  })
}
