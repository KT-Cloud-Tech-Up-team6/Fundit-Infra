resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  # argo-helm 저장소의 argo-cd-* 릴리스 중 최신 안정판(2026-09-17 확인)
  version = var.argocd_chart_version

  # repoServer 기본 livenessProbe timeoutSeconds(1초)가 너무 짧아
  # 232회 재시작이 관측됨(PR #67 리뷰). 5초로 늘린다.
  values = [
    yamlencode({
      repoServer = {
        livenessProbe = {
          timeoutSeconds = 5
        }
      }
    })
  ]
}
