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
