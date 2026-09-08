terraform {
  backend "s3" {
    bucket       = "fundit-tfstate-team6"
    key          = "bootstrap/terraform.tfstate" # bootstrap 전용 경로
    region       = "ap-northeast-2"
    profile      = "final"
    use_lockfile = true # S3 Native Lock
  }
}
