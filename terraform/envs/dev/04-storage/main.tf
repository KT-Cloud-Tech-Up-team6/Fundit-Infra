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
}

# 기존 bootstrap에서 생성된 S3 버킷을 무중단으로 04-storage로 이관하기 위한 import 블록
import {
  to = module.media_bucket.aws_s3_bucket.protected[0]
  id = "fundit-media-dev-team6"
}

import {
  to = module.media_bucket.aws_s3_bucket_versioning.this
  id = "fundit-media-dev-team6"
}

import {
  to = module.media_bucket.aws_s3_bucket_server_side_encryption_configuration.this
  id = "fundit-media-dev-team6"
}

import {
  to = module.media_bucket.aws_s3_bucket_public_access_block.this
  id = "fundit-media-dev-team6"
}
