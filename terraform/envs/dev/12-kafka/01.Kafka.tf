# 이슈 #65: 백엔드 6개 서비스가 이미 Kafka로 배선되어 있고(KafkaTopics.java),
# 로컬 docker-compose와 동일하게 apache/kafka 이미지를 옵션 없이 그대로 쓴다.
# 공식 저장소의 KRaft 단일 노드 예제(docker/examples/docker-compose-files/single-node/plaintext)
# 설정을 그대로 옮기고, PLAINTEXT_HOST(호스트 접속용) 리스너만 뺐다 — 클러스터 밖에서 붙을 일이 없다.
resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
  }
}

# Kafka의 cluster.id는 클러스터별로 고유해야 한다. 공식 예제는 샘플 값을 그대로 박아두는데,
# 여기서는 새로 생성해서 쓴다(16바이트, base64url, 패딩 없음 — Kafka가 요구하는 형식과 같다).
resource "random_id" "cluster_id" {
  byte_length = 16
}

resource "kubernetes_service" "kafka" {
  metadata {
    name      = "kafka"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }

  spec {
    cluster_ip = "None" # StatefulSet의 안정적인 DNS(pod-0.kafka...)를 위한 headless 서비스
    selector = {
      app = "kafka"
    }

    port {
      name = "plaintext"
      port = 9092
    }
  }
}

resource "kubernetes_stateful_set_v1" "kafka" {
  metadata {
    name      = "kafka"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }

  spec {
    service_name = kubernetes_service.kafka.metadata[0].name
    replicas     = 1

    selector {
      match_labels = {
        app = "kafka"
      }
    }

    template {
      metadata {
        labels = {
          app = "kafka"
        }
      }

      spec {
        # 이미지가 root가 아닌 appuser(uid/gid 1000)로 돈다. PVC는 기본 root 소유로 마운트되어
        # 컨테이너가 /var/lib/kafka/data에 못 써서 부팅 자체가 실패한다(실제 apply로 확인됨,
        # AccessDeniedException). fsGroup으로 볼륨 소유권을 맞춘다.
        security_context {
          fs_group = 1000
        }

        container {
          name  = "kafka"
          image = var.kafka_image

          port {
            container_port = 9092
          }

          env {
            name  = "KAFKA_NODE_ID"
            value = "1"
          }
          env {
            name  = "KAFKA_PROCESS_ROLES"
            value = "broker,controller"
          }
          env {
            name  = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
          }
          env {
            name  = "KAFKA_LISTENERS"
            value = "CONTROLLER://:29093,PLAINTEXT://:9092"
          }
          env {
            name = "KAFKA_ADVERTISED_LISTENERS"
            # 서비스가 headless라 이 DNS가 파드 IP로 바로 풀린다. 백엔드 서비스가 이 값으로 접속한다.
            value = "PLAINTEXT://kafka.kafka.svc.cluster.local:9092"
          }
          env {
            name  = "KAFKA_CONTROLLER_LISTENER_NAMES"
            value = "CONTROLLER"
          }
          env {
            name  = "KAFKA_INTER_BROKER_LISTENER_NAME"
            value = "PLAINTEXT"
          }
          env {
            name = "KAFKA_CONTROLLER_QUORUM_VOTERS"
            # 단일 노드라 broker와 controller가 같은 파드에서 돈다. 자기 자신을 localhost로 가리킨다.
            value = "1@localhost:29093"
          }
          env {
            name  = "CLUSTER_ID"
            value = random_id.cluster_id.b64_url
          }
          env {
            name = "KAFKA_LOG_DIRS"
            # PVC 마운트 경로(볼륨 루트) 바로 밑에는 EBS 포맷 시 생기는 lost+found가 있다.
            # Kafka LogManager가 이걸 topic-partition 디렉토리로 오인해 부팅 자체가 실패한다
            # (실제 apply로 확인됨). 마운트 경로 밑의 하위 디렉토리를 쓰면 해결된다.
            value = "/var/lib/kafka/data/logs"
          }
          env {
            name  = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS"
            value = "0"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
            value = "1"
          }
          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_SHARE_COORDINATOR_STATE_TOPIC_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name  = "KAFKA_SHARE_COORDINATOR_STATE_TOPIC_MIN_ISR"
            value = "1"
          }
          env {
            name  = "KAFKA_HEAP_OPTS"
            value = "-Xms${var.kafka_heap_size} -Xmx${var.kafka_heap_size}"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "768Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/kafka/data"
          }

          # kafka-broker-api-versions.sh(exec probe)는 JVM을 매번 새로 띄워서
          # cpu limit(500m) 아래에서 3.8~26초까지 걸린다(실측, 부하 상황 따라 편차 큼).
          # timeout_seconds를 늘리는 대신 TCP 포트 체크로 바꿔 이 비용 자체를 없앤다.
          readiness_probe {
            tcp_socket {
              port = 9092
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          # readiness만 있으면 브로커가 응답 없이 멈춰도 재시작이 안 된다.
          # 단일 레플리카 + headless 서비스라 그러면 서비스 전체가 접속 불가 상태로 남는다.
          # TCP 체크라 "포트는 열려있는데 안에서 멈춘" 상태는 못 잡는다 — 알고 감수하는 한계다.
          liveness_probe {
            tcp_socket {
              port = 9092
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 3
          }

          # CPU 경합이 심하면 부팅이 오래 걸릴 수 있다(실측 기준 추정). startup_probe가
          # 통과하기 전까지는 liveness가 아예 안 돌아서, 부팅 중인 파드를 죽이지 않는다.
          startup_probe {
            tcp_socket {
              port = 9092
            }
            period_seconds    = 5
            failure_threshold = 60 # 5분까지 부팅 유예
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"
        resources {
          requests = {
            storage = var.kafka_storage_size
          }
        }
      }
    }
  }
}
