output "web_acl_id" {
  description = "CloudFront에 연결할 WAF WebACL ID"
  value       = aws_wafv2_web_acl.cloudfront.id
}

output "web_acl_arn" {
  description = "CloudFront에 연결할 WAF WebACL ARN"
  value       = aws_wafv2_web_acl.cloudfront.arn
}
