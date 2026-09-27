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

# 라이브 녹화 영상(VOD) S3 버킷 및 IVS 출력 (이슈 #81)
output "video_bucket_name" {
  description = "라이브 녹화 영상(VOD) S3 버킷 이름"
  value       = module.video_bucket.bucket_id
}

output "video_bucket_arn" {
  description = "라이브 녹화 영상(VOD) S3 버킷 ARN"
  value       = module.video_bucket.bucket_arn
}

output "video_bucket_regional_domain_name" {
  description = "라이브 녹화 영상(VOD) S3 버킷 리전 도메인 주소"
  value       = module.video_bucket.bucket_regional_domain_name
}

# Ansible 보안 점검 파일 전송용 S3 버킷 출력 (이슈 #114)
output "ansible_transfer_bucket_name" {
  description = "Ansible 보안 점검 파일 전송용 S3 버킷 이름"
  value       = module.ansible_transfer_bucket.bucket_id
}

output "ansible_transfer_bucket_arn" {
  description = "Ansible 보안 점검 파일 전송용 S3 버킷 ARN"
  value       = module.ansible_transfer_bucket.bucket_arn
}

