# lifecycle 인자는 리터럴만 허용해 var.prevent_destroy를 직접 못 쓴다. count로 둘로 나눠 우회한다.
resource "aws_s3_bucket" "this" {
  count  = var.prevent_destroy ? 0 : 1
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket" "protected" {
  count  = var.prevent_destroy ? 1 : 0
  bucket = var.bucket_name
  tags   = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  bucket_id                   = var.prevent_destroy ? aws_s3_bucket.protected[0].id : aws_s3_bucket.this[0].id
  bucket_arn                  = var.prevent_destroy ? aws_s3_bucket.protected[0].arn : aws_s3_bucket.this[0].arn
  bucket_regional_domain_name = var.prevent_destroy ? aws_s3_bucket.protected[0].bucket_regional_domain_name : aws_s3_bucket.this[0].bucket_regional_domain_name
}

# 버전 관리
resource "aws_s3_bucket_versioning" "this" {
  bucket = local.bucket_id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# 기본 암호화 (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = local.bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 외부 퍼블릭 접근 차단
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS 설정 (선택 사항)
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = local.bucket_id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# 수명 주기 규칙 설정 (선택 사항)
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count      = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket     = local.bucket_id
  depends_on = [aws_s3_bucket_versioning.this]

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.status

      dynamic "filter" {
        for_each = rule.value.filter != null ? [rule.value.filter] : []
        content {
          prefix = filter.value.prefix
        }
      }

      dynamic "filter" {
        for_each = rule.value.filter == null ? [1] : []
        content {}
      }

      dynamic "transition" {
        for_each = rule.value.transitions != null ? rule.value.transitions : []
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []
        content {
          days = expiration.value.days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload != null ? [rule.value.abort_incomplete_multipart_upload] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value.days_after_initiation
        }
      }
    }
  }
}

