# Terraform tfstate 관리용 S3 bucket
module "tfstate_bucket" {
  source = "../../modules/s3"

  bucket_name       = var.state_bucket_name
  enable_versioning = true
  tags              = var.common_tags
}
# ----------------------------------------------------
# 개발 환경(dev) 미디어 파일 저장용 S3 버킷 추가
# ----------------------------------------------------
module "media_dev_bucket" {
  source = "../../modules/s3"
  bucket_name       = "fundit-media-dev-team6"
  enable_versioning = true
  tags              = var.common_tags
}
