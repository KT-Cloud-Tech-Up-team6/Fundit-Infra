# ──────────────────────────────────────────────────────────────────────────────
# ALB 알람 — EKS Ingress Controller가 생성한 ALB
# [Prerequisite] GitOps 배포 후 ALB가 생성된 상태여야 data.aws_lb.eks_alb가 정상 조회됨
# ──────────────────────────────────────────────────────────────────────────────

# ALB 5xx 응답 수 알람
# 오리진(EKS 파드) 또는 ALB 자체 오류 구분:
# - HTTPCode_Target_5XX_Count: 파드가 5xx 반환
# - HTTPCode_ELB_5XX_Count   : ALB가 5xx 반환 (타겟 없음, 타임아웃 등)
resource "aws_cloudwatch_metric_alarm" "alb_5xx_count" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "ALB가 1분 내 ${var.alb_5xx_threshold}건 이상의 5xx 응답을 반환했습니다. EKS 파드 상태 및 ALB 타겟 그룹을 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.eks_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]
  ok_actions    = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb-5xx-count"
  })
}

# ALB 타겟 응답 시간 알람 (p95)
resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-target-response-time-p95"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  threshold           = 2 # 2초
  alarm_description   = "ALB 타겟 응답 시간(p95)이 2초를 3분 이상 초과했습니다. EKS 파드 과부하 또는 DB 쿼리 병목을 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.eks_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb-target-response-time-p95"
  })
}

# ALB Unhealthy Host 알람
# CloudWatch UnHealthyHostCount 메트릭은 LoadBalancer와 TargetGroup 두 dimension 조합으로만 발행됩니다.
# LoadBalancer 단독 지정 시 데이터가 발행되지 않는 문제를 해결하기 위해, 타겟 그룹별(frontend, gateway)로 알람을 생성합니다.
# Unhealthy 타겟이 1개라도 발생하면 즉시 슬랙 알림 — 서비스 가용성 저하 선제 탐지
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_host_count" {
  for_each = data.aws_lb_target_group.eks

  alarm_name          = "${var.project_name}-${var.environment}-alb-${each.key}-unhealthy-host"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "ALB 타겟 그룹(${each.key}: ${each.value.name})에 Unhealthy 타겟이 발생했습니다. EKS 파드 재시작 또는 헬스체크 실패를 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.aws_lb.eks_alb.arn_suffix
    TargetGroup  = each.value.arn_suffix
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]
  ok_actions    = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb-${each.key}-unhealthy-host"
  })
}

