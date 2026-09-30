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
  description = "CloudFront edge WAF: AWS common and SQLi managed rule sets"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 1. [대용량 DoS 방어] 8KB 제한 완화에 따른 보완책으로 10MB 초과 비정상 페이로드 즉시 차단
  rule {
    name     = "SizeRestrictions_BODY_10MB"
    priority = 0

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          size_constraint_statement {
            field_to_match {
              body {
                oversize_handling = "MATCH"
              }
            }
            comparison_operator = "GT"
            size                = 10485760 # 10MB (10 * 1024 * 1024 bytes)
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        # CloudFront WAF의 본문 검사 한도(16KB)로 인해 oversize_handling = MATCH 시 16KB 초과 요청이 차단되므로,
        # 긴 본문 저장이 필요한 스토리 및 큐시트 경로는 이 크기 제한 규칙에서 명시적으로 제외한다.
        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  regex_match_statement {
                    regex_string = "^/api/v1/projects/[0-9a-zA-Z_-]+/story$"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
                statement {
                  regex_match_statement {
                    regex_string = "^/api/v1/lives/[0-9a-zA-Z_-]+/cue-sheet$"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-body-size-10mb"
      sampled_requests_enabled   = true
    }
  }

  # 2. AWS 관리형 Core rule set (일반적인 웹 공격 방어)
  # SizeRestrictions_BODY(8KB) 및 CrossSiteScripting_BODY는 Count로 오버라이드하여 WAF Label 발행
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

        # 레거시 8KB 제한은 Priority 0의 10MB 차단 룰로 대체
        rule_action_override {
          action_to_use {
            count {}
          }
          name = "SizeRestrictions_BODY"
        }

        # HTML 서식/태그 허용을 위해 Count 모드로 전환하고 Label 발행
        rule_action_override {
          action_to_use {
            count {}
          }
          name = "CrossSiteScripting_BODY"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # 3. [XSS 정밀 방어] 스토리(/story) 및 큐시트(/cuesheet) 예외 경로를 제외한 일반 API의 XSS 공격 즉시 차단
  rule {
    name     = "Block_XSS_Except_AllowedPaths"
    priority = 2

    action {
      block {}
    }

    statement {
      and_statement {
        # WAF CommonRuleSet이 감지한 XSS 레이블이 존재하는 경우
        statement {
          label_match_statement {
            scope = "LABEL"
            key   = "awswaf:managed:aws:core-rule-set:CrossSiteScripting_Body"
          }
        }

        # 단, 리치 텍스트 서식 저장이 허용된 프로젝트 스토리 및 라이브 큐시트 엔드포인트는 차단에서 제외
        statement {
          not_statement {
            statement {
              or_statement {
                statement {
                  regex_match_statement {
                    regex_string = "^/api/v1/projects/[0-9a-zA-Z_-]+/story$"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
                statement {
                  regex_match_statement {
                    regex_string = "^/api/v1/lives/[0-9a-zA-Z_-]+/cue-sheet$"
                    field_to_match {
                      uri_path {}
                    }
                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-block-xss-except-allowed"
      sampled_requests_enabled   = true
    }
  }

  # 4. AWS 관리형 SQL Injection rule set
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

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

  # WAF 차단 로그에 클라이언트 인증 토큰(Bearer JWT 등)이 평문으로 남지 않도록 마스킹
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

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
