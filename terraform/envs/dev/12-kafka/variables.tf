variable "kafka_image" {
  description = "Kafka 브로커 컨테이너 이미지. 백엔드 로컬 docker-compose와 버전을 맞춘다"
  type        = string
  default     = "apache/kafka:4.2.1"
}

variable "kafka_storage_size" {
  description = "Kafka 데이터(로그 세그먼트) PVC 크기"
  type        = string
  default     = "10Gi"
}

variable "kafka_heap_size" {
  description = "Kafka JVM 힙 크기(-Xms/-Xmx 동일 값). 컨테이너 메모리 limit보다 작아야 한다"
  type        = string
  default     = "512M"
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
