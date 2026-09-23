# QA 환경 인프라 변경 관리

이 문서는 통합 QA 환경(`infrastudy.store`)에서 인프라를 바꿀 때 지키는 절차를 다룬다.
[Issue #88](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/88) 기준이다.

## 적용 범위

QA 환경은 dev 환경 하나를 FE·BE·QA가 같이 쓴다.
인프라 변경의 영향은 테스트 중인 팀원 전체에게 간다.

별도 인프라 환경은 만들지 않는다.
EKS 클러스터와 NAT와 ALB와 노드 비용이 두 배가 된다.
도메인과 ACM 인증서와 결제 키와 IVS 채널도 두 벌을 관리해야 한다.
환경을 복제하는 대신 이 문서의 변경 절차로 영향을 줄인다.

## 변경 전 검증

모든 인프라 변경은 `feat/...` 같은 작업 브랜치와 PR로 반영한다.
`main`에 직접 커밋하지 않는다.
`main` 병합에는 승인 1개가 필요하다.

PR을 열면 `Terraform CI (PR Plan)`이 바뀐 레이어마다 아래를 실행한다(`.github/workflows/terraform-ci.yml`).

- `terraform fmt -check`
- `terraform validate`
- `terraform plan`
- plan 결과를 PR 코멘트로 올린다

CI는 PR이 `terraform/**` 또는 `.github/workflows/terraform-ci.yml`을 바꿀 때만 실행된다(`.github/workflows/terraform-ci.yml:7-9`).
`.github/workflows/terraform-cd.yml`만 바꾼 PR은 plan 없이 병합된다.
이 PR도 병합되면 CD가 아래 `root.yaml` 재적용까지 실행한다.

병합 전에 PR 코멘트의 plan에서 삭제와 재생성을 확인한다.
`destroy`나 `must be replaced`가 있으면 아래 위험도 기준으로 적용 시점을 정한다.

## 변경 반영

`main`에 병합되면 `Terraform CD (Main Apply)`가 바뀐 레이어를 순서대로 apply한다(`.github/workflows/terraform-cd.yml`).
apply 단계는 `dev-apply` 환경 승인을 받아야 실행된다.
승인자는 `jinsw1` `mshjgr` `BIN-829` 세 명이다.
승인자는 승인 전에 아래 위험도 기준의 적용 시점인지 확인한다.

`terraform/envs/dev/09-argocd/` 또는 `.github/workflows/terraform-cd.yml`이 바뀌면 CD는 apply 뒤에 Fundit-GitOps `main`의 `root.yaml`을 다시 적용한다(`.github/workflows/terraform-cd.yml:64` `:182`).
이때 `fundit-root` Application에서 `root.yaml`에 적힌 필드(`targetRevision` 등)를 수동으로 바꿨다면 `root.yaml` 값으로 돌아간다.
Argo CD Application을 수동으로 바꾼 상태라면 그 작업자와 확인한 뒤 승인한다.

## 위험도 분류

| 위험도 | 대상 작업 | 적용 시점 |
|---|---|---|
| Low (무중단) | WAF 규칙 · S3 CORS · HPA · 모니터링과 로깅 | QA 테스트 중에도 주간 상시 반영 |
| Medium (롤링) | 프론트엔드와 백엔드 컨테이너 이미지 · 환경변수 | 무중단 롤링 업데이트. 사전 공지 후 반영 |
| High (일시 단절) | NAT 인스턴스 교체 · VPC 라우팅 테이블 · PostgreSQL 메이저 패치와 재시작 | 정기 점검 윈도우(야간 22:00 이후). 사전 공지 후 반영 |

한 PR에 여러 위험도 작업이 섞이면 가장 높은 위험도를 따른다.
사전 공지는 팀 디스코드 채널에 올린다.

컨테이너 이미지와 환경변수 변경은 Fundit-GitOps 레포의 PR로 반영한다.
Fundit-GitOps `main` 병합에도 승인 1개가 필요하다.

## 배포 시간대

| 시기 | 방식 |
|---|---|
| QA 초기 | 사전 공지 후 수시 배포 |
| QA 안정화 | 매일 22:00~24:00 일괄 배포 |

## 데이터 보존

PostgreSQL 데이터는 EBS gp3 PVC에 저장한다(Fundit-GitOps `dev/cnpg/cluster.yaml`의 `gp3-retain` StorageClass).
파드가 재시작되어도 테스트 데이터는 지워지지 않는다.
DB 초기화는 팀 요청이 있을 때만 한다.
초기화는 자정 배치 또는 요청 시점에 실행한다.

## 점검 체크리스트

- [ ] 작업 브랜치와 PR로 변경했다
- [ ] PR plan 코멘트에서 삭제와 재생성 항목을 확인했다
- [ ] 위험도를 정했고 그 위험도의 적용 시점에 맞췄다
- [ ] Medium 이상이면 사전 공지했다
- [ ] argocd 레이어나 CD 워크플로 변경이면 Argo CD 수동 작업 여부를 확인했다
