terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# CloudFront(scope=CLOUDFRONT)용 WAF는 반드시 us-east-1에서 만들어야 함
resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-${var.environment}-cloudfront-waf"
  description = "CloudFront 앞단 웹 공격 차단 (Core rule set, SQLi rule set)"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 1. AWS 관리형 Core rule set (일반적인 웹 공격 방어)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # 2. AWS 관리형 SQL Injection rule set
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-sqli-rule-set"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# 차단 로그 수신용 로그 그룹. WAF 로깅 대상이라 이름이 aws-waf-logs- 로 시작해야 함
resource "aws_cloudwatch_log_group" "waf" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-${var.project_name}-${var.environment}"
  retention_in_days = 14
  tags              = var.tags
}

data "aws_caller_identity" "current" {
  provider = aws.us_east_1
}

data "aws_region" "current" {
  provider = aws.us_east_1
}

# WAF가 이 로그 그룹에 쓸 수 있도록 허용하는 리소스 정책. 없으면 로깅 설정 apply 시 권한 에러가 남
resource "aws_cloudwatch_log_resource_policy" "waf" {
  provider        = aws.us_east_1
  policy_name     = "${var.project_name}-${var.environment}-waf-logs"
  policy_document = data.aws_iam_policy_document.waf_logs.json
}

data "aws_iam_policy_document" "waf_logs" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  depends_on              = [aws_cloudwatch_log_resource_policy.waf]

  # ALLOW 트래픽까지 다 쌓이면 로그 비용이 늘어나서 차단된 요청만 남긴다
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }
    }
  }
}
