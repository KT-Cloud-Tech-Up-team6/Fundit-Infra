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
        # 주의(PR #146 리뷰 반영): config.filters를 지정하면 차트 기본
        # 필터가 "추가"가 아니라 "대체"된다. 원래 있던 Name kubernetes
        # 필터(kubernetes.namespace_name 등 메타데이터를 붙여주는 역할)를
        # 빼먹으면 아래 grep이 참조하는 필드 자체가 없어서 kube.* 로그가
        # 전부 걸러진다. 그래서 원본 kubernetes 필터를 그대로 유지하고
        # 그 뒤에 grep 필터를 덧붙인다(실제 클러스터의 현재 ConfigMap에서
        # 원본 내용 확인 완료).
        #
        # host.*(systemd, kubelet.service 로그)는 이번 필터 대상에 포함하지
        # 않음 — 애초 목적(워크로드 네임스페이스 노이즈·헬스체크 스팸 감소)
        # 밖의 범위이고, 이미 kubelet 하나로 좁게 받고 있어 양도 적음.
        filters = <<-EOT
          [FILTER]
              Name kubernetes
              Match kube.*
              Merge_Log On
              Keep_Log Off
              K8S-Logging.Parser On
              K8S-Logging.Exclude On

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