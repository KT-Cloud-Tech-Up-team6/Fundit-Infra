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
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
