# 이슈 #86: 분산 추적 저장소. 차트 기본값이 이미 단일 인스턴스 + 로컬 파일시스템
# 백엔드(storage.trace.backend: local)라 Loki와 마찬가지로 S3 없이 그대로 쓴다.
# OTLP(4317 grpc / 4318 http) 수신도 차트 기본값에 이미 켜져 있어 값 전달이 필요 없다.
# reportingEnabled만 꺼서 Grafana Labs로 나가는 익명 사용 통계 전송을 막는다.
resource "helm_release" "tempo" {
  name       = "tempo"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version

  values = [
    yamlencode({
      tempo = {
        reportingEnabled = false
        # 차트 기본값은 resources: {}(무제한)이다. dev 단일 인스턴스 기준으로 명시한다.
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      persistence = {
        enabled          = true
        storageClassName = "gp3"
        size             = var.tempo_storage_size
      }
    })
  ]
}
