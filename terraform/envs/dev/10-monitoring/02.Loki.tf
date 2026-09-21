# 이슈 #86: 로그 저장/색인. dev 규모(수십 GB/일 이하)라 공식 차트가 안내하는 대로
# SingleBinary 모드를 쓴다 — SimpleScalable/Distributed는 오브젝트 스토리지(S3)가 필수라
# S3 버킷과 IAM(IRSA)까지 새로 필요해진다. filesystem 스토리지 + useTestSchema로
# 그 의존성 자체를 없앤다(차트가 테스트/소규모 용도로 공식 안내하는 조합).
# gateway(nginx)·results/chunks 캐시(memcached)·canary는 dev 단일 인스턴스에 불필요한
# 파드만 늘려서 끈다.
resource "helm_release" "loki" {
  name       = "loki"
  namespace  = "monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version

  values = [
    yamlencode({
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "filesystem"
        }
        useTestSchema = true
      }
      deploymentMode = "SingleBinary"
      singleBinary = {
        replicas = 1
        persistence = {
          enabled      = true
          storageClass = "gp3"
          size         = var.loki_storage_size
        }
        # 차트 기본값은 resources: {}(무제한)이다. dev 단일 인스턴스 기준으로 명시한다.
        resources = {
          requests = {
            cpu    = "200m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      read    = { replicas = 0 }
      write   = { replicas = 0 }
      backend = { replicas = 0 }

      gateway      = { enabled = false }
      resultsCache = { enabled = false }
      chunksCache  = { enabled = false }
      lokiCanary   = { enabled = false }
      test         = { enabled = false }
    })
  ]
}
