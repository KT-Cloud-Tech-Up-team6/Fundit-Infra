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
}
