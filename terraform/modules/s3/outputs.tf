output "bucket_id" {
  value       = aws_s3_bucket.this.id
  description = "생성된 S3 버킷 ID (이름)"
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "생성된 S3 버킷 ARN"
}
