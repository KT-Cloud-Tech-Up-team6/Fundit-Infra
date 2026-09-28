# ──────────────────────────────────────────────────────────────────────────────
# Slack Notifier Lambda 패키징
# ──────────────────────────────────────────────────────────────────────────────
data "archive_file" "slack_notifier" {
  type        = "zip"
  source_file = "${path.module}/lambda/slack_notifier.py"
  output_path = "${path.module}/lambda/slack_notifier.zip"
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM — Slack Notifier Lambda 실행 역할
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "slack_notifier" {
  name = "${var.project_name}-${var.environment}-slack-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-slack-notifier-role"
  })
}

resource "aws_iam_policy" "slack_notifier" {
  name        = "${var.project_name}-${var.environment}-slack-notifier-policy"
  description = "Slack 알림 Lambda: CloudWatch Logs 기록 + Secrets Manager 조회"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:*"
      },
      {
        Sid    = "SecretsManagerGet"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        # 시크릿 이름에 -XXXXXX 무작위 suffix가 붙으므로 와일드카드 사용
        Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.slack_webhook_secret_name}*"
      },
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-slack-notifier-policy"
  })
}

resource "aws_iam_role_policy_attachment" "slack_notifier" {
  role       = aws_iam_role.slack_notifier.name
  policy_arn = aws_iam_policy.slack_notifier.arn
}

# ──────────────────────────────────────────────────────────────────────────────
# Slack Notifier Lambda (ap-northeast-2)
# NAT Failover Lambda와 역할 분리 — 이 함수는 알림 전용
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "slack_notifier" {
  filename         = data.archive_file.slack_notifier.output_path
  function_name    = "${var.project_name}-${var.environment}-slack-notifier"
  role             = aws_iam_role.slack_notifier.arn
  handler          = "slack_notifier.lambda_handler"
  source_code_hash = data.archive_file.slack_notifier.output_base64sha256
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SLACK_SECRET_NAME = var.slack_webhook_secret_name
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-slack-notifier"
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# SNS 토픽 1: ap-northeast-2 인프라 알람 (NAT CPU, ALB, S3, Lambda)
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "infra_alerts" {
  name = "${var.project_name}-${var.environment}-infra-alerts"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-infra-alerts"
  })
}

resource "aws_sns_topic_subscription" "slack_infra" {
  topic_arn = aws_sns_topic.infra_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

resource "aws_lambda_permission" "allow_sns_infra" {
  statement_id  = "AllowExecutionFromSNSInfraAlerts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.infra_alerts.arn
}

# ──────────────────────────────────────────────────────────────────────────────
# SNS 토픽 2: us-east-1 CloudFront/WAF 알람
# CloudFront 메트릭은 us-east-1에서만 제공되므로 SNS 토픽도 동일 리전에 생성
# SNS → Lambda는 크로스 리전 구독(ap-northeast-2)을 지원함
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "cloudfront_alerts" {
  provider = aws.us_east_1
  name     = "${var.project_name}-${var.environment}-cloudfront-alerts"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-cloudfront-alerts"
  })
}

resource "aws_sns_topic_subscription" "slack_cloudfront" {
  # us-east-1 SNS에서 ap-northeast-2 Lambda로 크로스 리전 구독
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.cloudfront_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

resource "aws_lambda_permission" "allow_sns_cloudfront" {
  statement_id  = "AllowExecutionFromSNSCloudFrontAlerts"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cloudfront_alerts.arn
}

# ──────────────────────────────────────────────────────────────────────────────
# 기존 NAT Failover SNS 토픽에 Slack Lambda 구독 추가
# 이중 NAT 장애(DUAL_FAILURE_ABORTED) 알림을 Slack에도 전달
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic_subscription" "slack_nat_failover" {
  topic_arn = data.aws_sns_topic.nat_failover_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

resource "aws_lambda_permission" "allow_sns_nat_failover" {
  statement_id  = "AllowExecutionFromSNSNATFailover"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = data.aws_sns_topic.nat_failover_alerts.arn
}
