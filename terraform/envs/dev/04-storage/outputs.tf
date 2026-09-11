output "db_backup_bucket_id" {
  description = "DB 백업 버킷 이름"
  value       = module.db_backup.bucket_id
}

output "db_backup_bucket_arn" {
  description = "DB 백업 버킷 ARN"
  value       = module.db_backup.bucket_arn
}

output "rag_source_docs_bucket_id" {
  description = "RAG 원본 문서 버킷 이름"
  value       = module.rag_source_docs.bucket_id
}

output "rag_source_docs_bucket_arn" {
  description = "RAG 원본 문서 버킷 ARN"
  value       = module.rag_source_docs.bucket_arn
}

output "media_bucket_name" {
  description = "미디어 S3 버킷 이름"
  value       = module.media_bucket.bucket_id
}

output "media_bucket_arn" {
  description = "미디어 S3 버킷 ARN"
  value       = module.media_bucket.bucket_arn
}

output "media_bucket_regional_domain_name" {
  description = "미디어 S3 버킷 리전 도메인 주소"
  value       = module.media_bucket.bucket_regional_domain_name
}
