# 이슈 #86: 노드별 컨테이너 로그 수집(DaemonSet). 기본 outputs가 존재하지 않는
# elasticsearch-master를 가리키고 있어 그대로 두면 재시도 에러만 쌓인다. Loki push API로
# 바꾸고, kubernetes 필터가 붙인 메타데이터를 auto_kubernetes_labels로 라벨화한다.
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  namespace  = "monitoring"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.fluent_bit_chart_version

  values = [
    yamlencode({
      config = {
        # 이슈 #(번호): kube-system/karpenter 등 불필요한 네임스페이스 로그와
        # Spring Boot 헬스체크(/actuator/health) 로그까지 전부 Loki로 쌓이고
        # 있어 디스크 낭비. 두 필터로 워크로드 네임스페이스만, 헬스체크는
        # 제외하고 남긴다.
        #
        # 확인 필요: $kubernetes['namespace_name']와 $log는 kubernetes 필터가
        # 붙이는 필드 이름 기준 추정값. 실제 태그(Match 패턴)와 필드명은
        # 차트 기본 inputs 설정을 따로 override하지 않은 상태라, 적용 후
        # 실제로 걸러지는지 로그로 확인 필요.
        filters = <<-EOT
          [FILTER]
              Name  grep
              Match kube.*
              Regex $kubernetes['namespace_name'] ^(dev|monitoring)$

          [FILTER]
              Name    grep
              Match   kube.*
              Exclude $log /actuator/health
        EOT
        outputs = <<-EOT
          [OUTPUT]
              Name loki
              Match *
              Host loki.monitoring.svc.cluster.local
              Port 3100
              Labels job=fluent-bit
              Auto_Kubernetes_Labels On
        EOT
      }
      # Fluent Bit은 모든 노드의 로그를 수집해야 하므로 일반 워크로드보다 먼저
      # Pod 슬롯을 확보한다. 노드의 maxPods가 가득 찬 경우 낮은 우선순위 Pod를
      # 다른 노드 또는 Karpenter 노드로 재배치해 DaemonSet Pending을 방지한다.
      priorityClassName = "system-node-critical"
      # taint가 있는 노드에서도 로그를 수집한다. stateful 노드(CNPG·Redis·Loki·Tempo)와 spot NodePool 노드.
      tolerations = [
        {
          key      = "workload"
          operator = "Equal"
          value    = "stateful"
          effect   = "NoSchedule"
        },
        {
          key      = "fundit.io/spot"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        },
      ]
      # 차트 기본값은 resources: {}(무제한)이다. 차트가 예시로 든 값을 그대로 쓴다.
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    })
  ]

  depends_on = [helm_release.loki]
}