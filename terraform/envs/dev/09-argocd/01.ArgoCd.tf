resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  # argo-helm 저장소의 argo-cd-* 릴리스 중 최신 안정판(2026-09-17 확인)
  version = var.argocd_chart_version
}
