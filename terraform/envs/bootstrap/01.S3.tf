# Terraform tfstate 관리용 S3 bucket
module "tfstate_bucket" {
  source = "../../modules/s3"

  bucket_name       = var.state_bucket_name
  enable_versioning = true
  tags              = var.common_tags
}
