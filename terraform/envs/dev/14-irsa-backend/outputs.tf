output "backend_s3_role_arn" {
  description = "백엔드 ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.backend_s3.arn
}

output "ai_s3_role_arn" {
  description = "AI ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.ai_s3.arn
}

output "ai_s3_role_name" {
  description = "AI ServiceAccount에 연결된 IAM Role 이름"
  value       = aws_iam_role.ai_s3.name
}

output "live_ivs_role_arn" {
  description = "Live ServiceAccount에 연결할 IAM Role ARN. Fundit-GitOps의 ServiceAccount annotation에서 참조한다"
  value       = aws_iam_role.live_ivs.arn
}

output "live_ivs_role_name" {
  description = "Live ServiceAccount에 연결된 IAM Role 이름"
  value       = aws_iam_role.live_ivs.name
}

output "live_s3_policy_arn" {
  description = "Live ServiceAccount에 연결된 S3 IAM 정책 ARN"
  value       = aws_iam_policy.live_s3.arn
}

output "live_recording_queue_url" {
  description = "Live 서비스가 IVS 녹화 완료 이벤트를 수신할 SQS 큐 URL"
  value       = aws_sqs_queue.live_recording.url
}

output "live_recording_queue_arn" {
  description = "IVS 녹화 완료 이벤트 SQS 큐 ARN"
  value       = aws_sqs_queue.live_recording.arn
}

output "live_recording_dlq_url" {
  description = "IVS 녹화 완료 이벤트 Dead Letter Queue URL"
  value       = aws_sqs_queue.live_recording_dlq.url
}

output "live_recording_event_rule_arn" {
  description = "IVS 녹화 완료 EventBridge 규칙 ARN"
  value       = aws_cloudwatch_event_rule.live_recording.arn
}

