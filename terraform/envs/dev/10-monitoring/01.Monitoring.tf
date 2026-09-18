# Helm release 이름을 kube-prometheus-stack으로 고정한다.
# 차트가 기본으로 만드는 Prometheus CR의 ruleSelector가 release 이름과 같은 값의
# release 라벨을 요구하는데, Fundit-GitOps의 dev/monitoring/alerts.yaml:7에 이미
# release: kube-prometheus-stack 라벨이 박혀 있어 이름을 맞춰야 PrometheusRule이 선택된다.
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  # prometheus-community/helm-charts 저장소의 kube-prometheus-stack-* 릴리스 중 최신 안정판(2026-09-17 확인)
  version = var.kube_prometheus_stack_chart_version

  # 기본값은 emptyDir이라 파드 재시작(노드 교체, Karpenter consolidation 등) 시
  # 메트릭이 전부 사라진다. gp3 PVC로 영속화한다. DB처럼 보존이 필수는 아니라
  # gp3-retain이 아니라 gp3를 쓴다(이슈 #69).
  # retentionSize를 안 두면 retention(기간, 차트 기본 10d)만 보고 지우기 때문에
  # 메트릭이 늘면 10일 전에 PVC가 찰 수 있다. PVC 크기(prometheus_storage_size)의
  # 80%로 잡아 압축·WAL이 쓸 여유를 남긴다.
  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retentionSize = var.prometheus_retention_size
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
        }
      }
    })
  ]
}
