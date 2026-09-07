---
name: "🔄 인프라 변경 및 작업 계획서 (Change Request)"
about: "기존 인프라 수정, 스펙 증설, 보안 정책 변경 작업을 계획합니다."
title: "[Change]: "
labels: ["change-request", "maintenance"]
assignees: ""
---

## 🎯 변경 목적 및 개요 (Purpose)
> 인프라를 변경해야 하는 사유를 명시해주세요. (예: 트래픽 증가로 인한 EC2 스케일업, 보안 감사 조치 등)

- 

## 🗺️ 변경 범위 (Scope of Changes)
- **영향 받는 환경**: `sandbox` / `dev` / `prod`
- **영향 받는 리소스**: (예: `dev-ec2`, `alb-sg`, `route53`)
- **서비스 중단/다운타임 예상 여부**:
  - [ ] 다운타임 없음 (무중단 작업)
  - [ ] 일시적 재시작/지연 발생 예상 (예상 시간: 분)

## 📝 작업 절차 (Action Plan)
1. 사전 준비 작업: 
2. 테라폼 코드 수정 및 PR 생성:
3. 배포 및 반영 순서:
4. 사후 검증(Healthcheck):

## 🔙 롤백 계획 (Rollback Plan)
> 작업 중 예기치 못한 장애가 발생했을 때 어떻게 이전 상태로 되돌릴 것인지 적어주세요.

- 
