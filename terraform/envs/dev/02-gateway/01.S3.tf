# CloudFront OAC(Origin Access Control)만 bootstrap의 S3 미디어 객체를 읽을 수 있도록 허용하는 버킷 정책
resource "aws_s3_bucket_policy" "media_oac_policy" {
  bucket = data.terraform_remote_state.bootstrap.outputs.media_dev_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${data.terraform_remote_state.bootstrap.outputs.media_dev_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.cloudfront_distribution_arn
          }
        }
      }
    ]
  })
}
