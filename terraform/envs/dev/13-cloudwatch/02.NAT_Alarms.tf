# ──────────────────────────────────────────────────────────────────────────────
# NAT 인스턴스 CPU 사용률 알람 (NAT-1, NAT-2)
# StatusCheckFailed 알람은 01-network의 nat-instance 모듈에 이미 존재 — 중복 방지
# ──────────────────────────────────────────────────────────────────────────────
locals {
  # 01-network의 nat_asg_names(ASG Self-Healing 모드) 참조 (fallback으로 표준 명명 규칙 적용)
  nat_asg_names = try(
    length(data.terraform_remote_state.network.outputs.nat_asg_names) > 0 ? data.terraform_remote_state.network.outputs.nat_asg_names : null,
    [
      "${var.project_name}-${var.environment}-nat-asg-1",
      "${var.project_name}-${var.environment}-nat-asg-2"
    ]
  )
}

resource "aws_cloudwatch_metric_alarm" "nat_cpu_high" {
  count = length(local.nat_asg_names)

  alarm_name          = "${var.project_name}-${var.environment}-nat-${count.index + 1}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.nat_cpu_threshold
  alarm_description   = "NAT ASG ${local.nat_asg_names[count.index]}의 CPU 사용률이 ${var.nat_cpu_threshold}%를 3분 이상 초과했습니다. 트래픽 과부하 또는 Failover 루프를 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = local.nat_asg_names[count.index]
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]
  ok_actions    = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}-cpu-high"
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# NAT Failover Lambda 에러 알람
# Lambda 자체 예외(boto3 오류, 권한 거부 등) 발생 시 즉시 알림
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "nat_failover_lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-nat-failover-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Failover Lambda 함수에서 오류가 발생했습니다. 페일오버/페일백이 정상 실행되지 않을 수 있습니다. 즉시 확인하세요."
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = data.aws_lambda_function.nat_failover.function_name
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]
  ok_actions    = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-failover-lambda-errors"
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# NAT Failover Lambda 실행 시간 알람
# timeout=30초 설정 대비, 10초 초과 시 로직 이상 또는 EC2 API 응답 지연 가능성 경고
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "nat_failover_lambda_duration" {
  alarm_name          = "${var.project_name}-${var.environment}-nat-failover-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10000 # 10,000ms = 10초
  alarm_description   = "NAT Failover Lambda 실행 시간이 10초를 초과했습니다. EC2 API 지연 또는 무한 루프 위험이 있습니다."
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = data.aws_lambda_function.nat_failover.function_name
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-failover-lambda-duration"
  })
}
