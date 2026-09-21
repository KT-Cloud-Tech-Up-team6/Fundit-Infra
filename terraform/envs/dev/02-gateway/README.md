# 02-gateway 레이어 (CloudFront, Route53, WAF)

## 📌 개요
`02-gateway` 레이어는 FundIt 서비스의 글로벌 진입점(CDN), 도메인/DNS, SSL 인증서 및 웹 방화벽(WAF)을 관리합니다.

---

## ⚠️ 배포 순서 및 전제조건 (Prerequisites)

1. **EKS Ingress ALB 사전 프로비저닝 (GitOps 의존성)**
   - `02-gateway/data.tf`의 `data.aws_lb.eks_alb`는 Terraform이 아닌 **GitOps(EKS Ingress + AWS Load Balancer Controller)**에 의해 생성된 ALB를 태그(`ingress.k8s.aws/stack: fundit-alb`)로 조회합니다.
   - 따라서 **EKS 클러스터 및 Ingress 리소스가 먼저 배포되어 ALB가 AWS 상에 프로비저닝된 상태에서 `02-gateway`를 Apply**해야 합니다.

2. **Route53 Hosted Zone**
   - 도메인(`infrastudy.store`)의 Route53 퍼블릭 호스팅 영역이 사전 등록되어 있어야 합니다.

3. **ACM SSL 인증서 (와일드카드 지원)**
   - `infrastudy.store` 및 `*.infrastudy.store` 와일드카드 SAN을 포함하여 us-east-1 리전에 생성 및 DNS 자동 검증됩니다.
