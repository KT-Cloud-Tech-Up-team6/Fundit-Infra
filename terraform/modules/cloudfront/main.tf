# 1. 관리형 캐시 정책 조회
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled" # EC2 동적 API용 (캐시 OFF)
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized" # S3 미디어/이미지용 (캐시 ON)
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewerAndCloudFrontHeaders-2022-06"
}

# 2. S3 보안 통제를 위한 OAC (Origin Access Control) 생성
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project_name}-${var.environment}-s3-oac"
  description                       = "OAC for ${var.project_name} S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3. CloudFront 배포 생성 (다중 오리진: EC2 + S3)
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} ${var.environment} CloudFront CDN"
  price_class     = "PriceClass_200" # 한국, 아시아, 북미, 유럽 엣지 포함
  web_acl_id      = var.web_acl_id   # WAF WebACL ARN, null이면 미연결
  # ----------------------------------------------------
  # 오리진 1: 개발용 EC2 인스턴스 (웹/API)
  # ----------------------------------------------------
  origin {
    domain_name = var.app_origin_domain # 찾아갈 원본 서버 주소
    origin_id   = var.app_origin_id     # Cloudfront 내부에서 부를 식별자
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # EC2 자체는 HTTP로 받고 CloudFront가 HTTPS 제공
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  # ----------------------------------------------------
  # 오리진 2: S3 미디어 버킷 (상품 이미지/동영상)
  # ----------------------------------------------------
  origin {
    domain_name              = var.media_origin_domain
    origin_id                = var.media_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }
  # ----------------------------------------------------
  # 동작 1: 기본 경로 (/*) -> App 서버로 전달 (캐시 OFF)
  # ----------------------------------------------------
  default_cache_behavior {
    target_origin_id         = var.app_origin_id                                            # 도착지 : App 서비스
    viewer_protocol_policy   = "redirect-to-https"                                          # http -> https로 전환
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"] # 모든 메서드 허용
    cached_methods           = ["GET", "HEAD"]                                              # GET, HEAD만 캐시
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id         # 캐시 비활성화
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id      # 모든 헤더 전달
  }
  # ----------------------------------------------------
  # 동작 2: 미디어 경로 (/media/*) -> S3로 전달 (캐시 ON) 
  # ----------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/media/*"
    target_origin_id       = var.media_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }
  # ----------------------------------------------------
  # 기타 기본 보안 및 인증서
  # ----------------------------------------------------
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  # CloudFront 기본 무료 SSL 인증서 (*.cloudfront.net)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-cdn"
    }
  )
}
