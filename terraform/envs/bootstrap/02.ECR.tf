# 애플리케이션 도커 이미지 저장소 (ECR) 모듈 호출
module "ecr" {
  source = "../../modules/ecr"

  repository_names = var.ecr_repository_names
  tags             = var.common_tags
}