# ──────────────────────────────────────────────────────────────────────────────
# CloudFront / WAF 알람
# 주의: CloudFront 메트릭은 us-east-1에서만 제공됨 → provider = aws.us_east_1 필수
#       alarm_actions도 동일 리전 SNS 토픽(cloudfront_alerts)을 가리켜야 함
# ──────────────────────────────────────────────────────────────────────────────

# CloudFront 5xx 에러율 알람
# 오리진 장애(ALB 다운, EKS 파드 크래시) 또는 CloudFront 설정 오류 시 급증
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_error_rate" {
  provider = aws.us_east_1

  alarm_name          = "${var.project_name}-${var.environment}-cloudfront-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudfront_5xx_threshold
  alarm_description   = "CloudFront 5xx 에러율이 ${var.cloudfront_5xx_threshold}%를 초과했습니다. ALB 또는 EKS 파드 상태를 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = data.terraform_remote_state.gateway.outputs.cloudfront_distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.cloudfront_alerts.arn]
  ok_actions    = [aws_sns_topic.cloudfront_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-cloudfront-5xx-error-rate"
  })
}

# CloudFront 오리진 응답 지연 알람
# [주의] OriginLatency 메트릭은 추가 비용이 발생하는 "추가 메트릭(Additional Metrics)"임
# CloudFront 콘솔 > 배포 선택 > 모니터링 > "추가 메트릭 활성화" 후 사용 가능
resource "aws_cloudwatch_metric_alarm" "cloudfront_origin_latency" {
  provider = aws.us_east_1

  alarm_name          = "${var.project_name}-${var.environment}-cloudfront-origin-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 300
  # OriginLatency는 퍼센타일 통계 지원
  extended_statistic  = "p90"
  threshold           = 2000 # 2,000ms = 2초
  alarm_description   = "CloudFront 오리진 응답 시간(p90)이 2초를 초과했습니다. ALB 타겟 응답 지연 또는 EKS 파드 과부하를 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = data.terraform_remote_state.gateway.outputs.cloudfront_distribution_id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.cloudfront_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-cloudfront-origin-latency"
  })
}

# WAF 차단 요청 급증 알람
# DDoS, 봇 공격, 비정상 크롤링 패턴 감지
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  provider = aws.us_east_1

  alarm_name          = "${var.project_name}-${var.environment}-waf-blocked-requests-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 500 # 5분 내 500건 차단 시 알림
  alarm_description   = "WAF가 5분 내 500건 이상의 요청을 차단했습니다. 공격 또는 비정상 트래픽 패턴을 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.waf_web_acl_name
    Region = "us-east-1"
    Rule   = "ALL"
  }

  alarm_actions = [aws_sns_topic.cloudfront_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-waf-blocked-requests-spike"
  })
}
