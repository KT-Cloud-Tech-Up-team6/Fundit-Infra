## PR 개요
> 이번 PR에서 변경된 인프라 내용의 요약을 적어주세요.

- 연관 이슈: close #

---

## 변경 유형 (Type of Change)
- [ ] 새로운 인프라 리소스 추가 (New Feature)
- [ ] 기존 인프라 설정 수정/개선 (Configuration Change)
- [ ] 인프라 리소스 삭제 또는 마이그레이션 (Deprecation/Removal)
- [ ] 테라폼 오류 또는 인프라 버그 수정 (Bug Fix)
- [ ] 문서 수정 또는 주석 개선 (Documentation)
- [ ] CI/CD 파이프라인 또는 스크립트 수정 (CI/CD)

---

## 영향 받는 환경 및 계층
- **환경 (Environment)**:
  - [ ] `bootstrap` (공통/영속 자원)
  - [ ] `sandbox`
  - [ ] `dev`
  - [ ] `prod`
- **계층 (Layer)**:
  - [ ] `01-network` (VPC, Subnet, NAT, IGW)
  - [ ] `02-gateway` (WAF, CloudFront, ALB)
  - [ ] `03-compute` (EC2 / EKS / IRSA)
  - [ ] `modules/*` (공통 모듈 수정)

---

## Terraform Plan 결과
> 로컬 또는 CI에서 실행한 `terraform plan` 요약을 작성해주세요.

```text
Plan: X to add, Y to change, Z to destroy.
```

- [ ] **[주의] 파괴적 변경(Destroy) 여부**: 삭제되는 리소스가 있는 경우 반드시 체크하고 영향도를 명시하세요.
  - 삭제 대상: 

---

## 체크리스트 (Checklist)
- [ ] `terraform fmt`를 실행하여 코드 포맷팅을 맞추었습니다.
- [ ] `terraform validate`를 실행하여 문법 검증을 통과했습니다.
- [ ] 새로운 변수(variables.tf) 및 출력값(outputs.tf)에 `description`과 `type`을 작성했습니다.
- [ ] Secret(비밀키, 패스워드 등)이 하드코딩되거나 Git에 커밋되지 않았음을 확인했습니다.
- [ ] README나 관련 인프라 문서 업데이트가 필요한 경우 반영했습니다.

---

## 테스트 및 검증 결과 (스크린샷 등)
> AWS 콘솔 확인 스크린샷, curl 테스트 결과, CLI 실행 결과 등을 첨부해주세요.
