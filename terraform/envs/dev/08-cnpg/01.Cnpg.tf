# 백업(barman-cloud)은 오퍼레이터가 아니라 각 PostgreSQL 인스턴스 파드가 직접 수행하므로,
# IRSA는 오퍼레이터의 ServiceAccount가 아니라 Cluster별 ServiceAccount에 붙인다.
# 이슈 #20 본문은 "오퍼레이터가 IRSA를 쓴다"고 적혀 있으나, CNPG의 실제 백업 동작 주체를
# 기준으로 이렇게 구성했다. PR에서 이 부분 확인 필요.
module "cnpg" {
  source = "../../../modules/cnpg"

  cluster_name          = data.terraform_remote_state.eks.outputs.cluster_name
  oidc_provider_arn     = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_provider_url     = data.terraform_remote_state.eks.outputs.oidc_provider_url
  backup_bucket_name    = data.terraform_remote_state.storage.outputs.db_backup_bucket_id
  backup_namespace      = var.backup_namespace
  postgres_cluster_name = var.postgres_cluster_name

  tags = var.common_tags
}

resource "helm_release" "cnpg" {
  name             = "cnpg"
  namespace        = "cnpg-system"
  create_namespace = true
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  # cloudnative-pg/charts 저장소의 cloudnative-pg-* 릴리스 중 최신 안정판(2026-09-14 확인)
  version = var.cnpg_chart_version
}
