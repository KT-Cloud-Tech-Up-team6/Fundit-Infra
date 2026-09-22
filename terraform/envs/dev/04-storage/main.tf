# CNPG 백업(Full Backup, WAL Archive) 저장용, 버전 관리 활성화
module "db_backup" {
  source = "../../../modules/s3"

  bucket_name       = "${var.project_name}-${var.environment}-s3-db-backup"
  enable_versioning = true
  prevent_destroy   = true
  tags              = var.common_tags
}

# RAG 파이프라인 원본 문서 업로드용
module "rag_source_docs" {
  source = "../../../modules/s3"

  bucket_name = "${var.project_name}-${var.environment}-s3-rag-source-docs"
  tags        = var.common_tags
}

# 미디어 파일 저장용 S3 버킷 (bootstrap에서 이관, 이슈 #30)
module "media_bucket" {
  source = "../../../modules/s3"

  bucket_name       = "fundit-media-dev-team6"
  enable_versioning = true
  prevent_destroy   = true
  tags              = var.common_tags

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "PUT", "POST", "HEAD"]
      allowed_origins = [
        "https://infrastudy.store",
        "http://localhost:3000"
      ]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]
}

# 라이브 녹화 영상(VOD) 저장용 S3 버킷 (이슈 #81)
module "video_bucket" {
  source = "../../../modules/s3"

  bucket_name       = "fundit-video-dev-team6"
  enable_versioning = false # 대용량 비디오의 중복 저장 및 비용 증가 방지
  prevent_destroy   = true
  tags              = var.common_tags

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = [
        "https://infrastudy.store",
        "http://localhost:3000"
      ]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]

  lifecycle_rules = [
    {
      id     = "vod-lifecycle"
      status = "Enabled"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 365
      }
      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    }
  ]
}

# AWS IVS 실시간 방송 자동 녹화 설정 (Recording Configuration)
resource "aws_ivs_recording_configuration" "this" {
  name = "${var.project_name}-${var.environment}-ivs-recording-config"

  destination_configuration {
    s3 {
      bucket_name = module.video_bucket.bucket_id
    }
  }

  thumbnail_configuration {
    recording_mode          = "INTERVAL"
    target_interval_seconds = 60
  }

  recording_reconnect_window_seconds = 60

  tags = var.common_tags
}

