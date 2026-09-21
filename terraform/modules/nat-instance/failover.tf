data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# 1. Lambda 코드 압축 (zip)
data "archive_file" "failover_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/failover.py"
  output_path = "${path.module}/lambda/failover.zip"
}

# 2. Lambda 실행용 IAM 역할
resource "aws_iam_role" "failover_lambda" {
  name = "${var.project_name}-${var.environment}-nat-failover-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-failover-role"
    }
  )
}

# 3. Lambda 실행 권한 (CloudWatch Logs + EC2 라우팅 교체)
resource "aws_iam_policy" "failover_lambda" {
  name        = "${var.project_name}-${var.environment}-nat-failover-policy"
  description = "IAM policy for NAT instance HA failover Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:*"
      },
      {
        Sid    = "EC2RouteDescribe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeRouteTables",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2RouteManagement"
        Effect = "Allow"
        Action = [
          "ec2:ReplaceRoute",
          "ec2:CreateRoute"
        ]
        Resource = [
          for rtb_id in var.private_route_table_ids :
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:route-table/${rtb_id}"
        ]
      },
      {
        Sid    = "SNSPublishAlerts"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.failover_alerts.arn
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-failover-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "failover_lambda" {
  role       = aws_iam_role.failover_lambda.name
  policy_arn = aws_iam_policy.failover_lambda.arn
}

# 4. 페일오버 / 페일백 Lambda 함수
resource "aws_lambda_function" "failover" {
  filename         = data.archive_file.failover_lambda.output_path
  function_name    = "${var.project_name}-${var.environment}-nat-failover"
  role             = aws_iam_role.failover_lambda.arn
  handler          = "failover.lambda_handler"
  source_code_hash = data.archive_file.failover_lambda.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ROUTE_TABLE_A_ID    = var.private_route_table_ids[0]
      ROUTE_TABLE_C_ID    = var.private_route_table_ids[1]
      NAT_1_ENI_ID        = aws_instance.nat[0].primary_network_interface_id
      NAT_2_ENI_ID        = aws_instance.nat[1].primary_network_interface_id
      NAT_1_INSTANCE_ID   = aws_instance.nat[0].id
      NAT_2_INSTANCE_ID   = aws_instance.nat[1].id
      NAT_1_TAG_NAME      = "${var.project_name}-${var.environment}-nat-1"
      NAT_2_TAG_NAME      = "${var.project_name}-${var.environment}-nat-2"
      ALERT_SNS_TOPIC_ARN = aws_sns_topic.failover_alerts.arn
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-failover"
    }
  )
}

# 5. CloudWatch Metric Alarm (NAT-1, NAT-2 StatusCheckFailed 감시)
resource "aws_cloudwatch_metric_alarm" "nat_status" {
  count               = length(aws_instance.nat)
  alarm_name          = "${var.project_name}-${var.environment}-nat-${count.index + 1}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Status check failed for NAT instance ${count.index + 1}. Triggers failover/failback."

  # NAT 인스턴스 중지(stopped) 등으로 지표 수집이 중단될 때 INSUFFICIENT_DATA로 방치되지 않고 ALARM으로 처리
  treat_missing_data = "breaching"

  dimensions = {
    InstanceId = aws_instance.nat[count.index].id
  }

  alarm_actions = [aws_lambda_function.failover.arn]
  ok_actions    = [aws_lambda_function.failover.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}-status-check"
    }
  )
}

# 6. CloudWatch Alarm이 Lambda 함수를 호출할 수 있도록 리소스 기반 권한 부여
resource "aws_lambda_permission" "allow_cloudwatch_alarm" {
  count         = length(aws_instance.nat)
  statement_id  = "AllowExecutionFromCloudWatchAlarm-${count.index + 1}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.nat_status[count.index].arn
}

# 7. DUAL_FAILURE_ABORTED 등 치명적 장애 알림용 SNS 토픽
# (운영자 이메일, Slack Chatbot, Discord Webhook Lambda 등 향후 구독자를 연결할 수 있는 알림 Hub)
resource "aws_sns_topic" "failover_alerts" {
  name = "${var.project_name}-${var.environment}-nat-failover-alerts"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-failover-alerts"
    }
  )
}

# 7-1. 운영자 이메일 긴급 알림 구독 (선택 사항, Slack/Discord 웹훅 연동 전 임시/백업용)
resource "aws_sns_topic_subscription" "email_alert" {
  count     = var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.failover_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 8. EventBridge: NAT 인스턴스 상태 감지 (인스턴스 교체 시 Route Reconciliation 및 즉각 Failover)
# 테라폼 프로비저닝 순서 레이스 컨디션을 방지하기 위해 instance-id 필터를 제거하고,
# Lambda 내부에서 Name 태그(fundit-dev-nat-*)로 대상을 판별합니다.
resource "aws_cloudwatch_event_rule" "nat_instance_state" {
  name        = "${var.project_name}-${var.environment}-nat-instance-state"
  description = "Triggers NAT failover Lambda for route reconciliation (running) and fast failover (stopped/terminated)"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running", "stopped", "shutting-down", "terminated"]
    }
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-instance-state"
    }
  )
}

resource "aws_cloudwatch_event_target" "lambda_reconcile" {
  rule      = aws_cloudwatch_event_rule.nat_instance_state.name
  target_id = "NatFailoverLambdaReconcile"
  arn       = aws_lambda_function.failover.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeStateChange"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nat_instance_state.arn
}


