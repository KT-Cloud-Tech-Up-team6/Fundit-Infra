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

        # 이슈 #(번호): 로그 자동 삭제 정책. compactor가 없으면 20Gi gp3 PVC가
        # 시간이 지날수록 계속 차오르기만 해서 언젠가 Full이 난다.
        # retention_period는 "168h"(7일) 기준, 14일로 늘리려면 "336h"로 변경.
        limits_config = {
          retention_period = "168h"
        }
        compactor = {
          retention_enabled = true
          # 최신 Loki 버전은 retention_enabled=true일 때 이 값을 요구한다.
          # 적용 후 파드가 안 뜨면 이 줄부터 의심할 것(버전에 따라 불필요할 수 있음).
          delete_request_store = "filesystem"
        }
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
        # stateful-ng 노드의 taint(workload=stateful:NoSchedule)를 통과하기 위한 톨러레이션
        tolerations = [
          {
            key      = "workload"
            operator = "Equal"
            value    = "stateful"
            effect   = "NoSchedule"
          }
        ]
        # stateful-ng 노드(role=stateful)에만 스케줄되도록 고정
        affinity = {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key      = "role"
                      operator = "In"
                      values   = ["stateful"]
                    }
                  ]
                }
              ]
            }
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