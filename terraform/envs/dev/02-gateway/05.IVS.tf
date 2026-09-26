# AWS IVS 실시간 방송 자동 녹화 설정 (Recording Configuration) (이슈 #81, #107)
# VOD S3 버킷 정책(video_bucket_policy)이 먼저 적용되어 있어야 IVS가 S3 쓰기 권한을 검증하고 정상 생성됨
resource "aws_ivs_recording_configuration" "this" {
  count = local.video_bucket_name != null ? 1 : 0
  name  = "${var.project_name}-${var.environment}-ivs-recording-config"

  destination_configuration {
    s3 {
      bucket_name = local.video_bucket_name
    }
  }

  thumbnail_configuration {
    recording_mode          = "INTERVAL"
    target_interval_seconds = 60
  }

  recording_reconnect_window_seconds = 60

  # 버킷 정책이 먼저 생성되어야 IVS의 S3 접근 권한 검증(CreateRecordingConfiguration)을 통과함
  depends_on = [
    aws_s3_bucket_policy.video_bucket_policy
  ]
}
