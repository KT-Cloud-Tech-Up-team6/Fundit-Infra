output "bootstrap_servers" {
  description = "백엔드 서비스가 KAFKA_BOOTSTRAP_SERVERS에 넣을 값(같은 클러스터 안에서 접속하는 경우)"
  value       = "kafka.kafka.svc.cluster.local:9092"
}
