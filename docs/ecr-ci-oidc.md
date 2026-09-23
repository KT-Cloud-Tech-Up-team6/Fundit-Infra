# 애플리케이션 이미지 CI의 ECR Push 인증

Fundit-Infra [Issue #37](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/37)의
인프라 코드 부분이다. GitHub Actions가 장기 AWS Access Key 없이 임시 자격 증명을 받아
자기 ECR 저장소에 이미지를 Push하도록 한다. 현재 대상은 개발 이미지 CI다.

## 구성과 담당

| 항목 | 내용 |
|---|---|
| 선언 | `terraform/envs/bootstrap/04.ECRPushOIDC.tf` |
| 공통 인증 공급자 | 기존 `aws_iam_openid_connect_provider.github` 재사용 |
| Backend | `Fundit-backend`의 `develop` → `fundit-backend-ci-role` → 다른 CI Role 소유 저장소를 제외한 서비스별 저장소 |
| Frontend | `Fundit-FE`의 `main` → `fundit-frontend-ci-role` → `fundit-frontend` |
| AI cuesheet | `Fundit-Ai-cuesheet`의 `main` → `fundit-ai-cuesheet-ci-role` → `fundit-ai-cuesheet` |
| AI funding story | `Fundit-AI-Funding-Story`의 `main` → `fundit-ai-funding-story-ci-role` → `fundit-ai-funding-story` |
| AI copilot | `Fundit-Ai-copilot`의 `main` → `fundit-ai-copilot-ci-role` → `fundit-ai-copilot` |
| AI highlight | `Funddit-Ai-highlight`의 `master` → `fundit-ai-highlight-ci-role` → `fundit-ai-highlight` |
| 출력 | `ecr_ci_role_arns`의 `backend` / `frontend` / `ai_cuesheet` / `ai_funding_story` / `ai_copilot` / `ai_highlight`, 기존 `ecr_repository_urls` |
| 조용빈 | 이미지 CI 인증 코드·검증, GitOps 이미지 계약과 후속 파이프라인 연결 |
| 이성규와 협업 | AWS IAM/ECR 검토, 실제 bootstrap plan/apply, EC2 Pull 권한·원격 접속 방식 |

기존 Terraform 실행 Role의 trust policy와 OIDC 공급자는 이 변경의 수정 대상이
아니다. [Issue #54](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/54)는
별도 담당자가 진행하며, 그 복구가 끝나기 전에도 여기의 코드 검증은 가능하다.
`bootstrap` 변경은 기존 Terraform CI/CD의 감지 대상이므로 실제 반영 일정은 AWS 담당자와
협의한다. main 병합 후 CD가 실행될 수 있다는 점도 함께 확인한다.

bootstrap CI/CD는 ignore된 팀별 tfvars를 사용하지 않는다. 공통 태그 변수의 기본값을
네이밍규약서와 실제 자원에 적용된 `Project=Fundit`, `Team=Team6`, `ManagedBy=Terraform`으로
맞춰, plan/apply가 기존 자원에서 태그를 제거하지 않게 한다. 명시적인 tfvars가 있으면
Terraform 변수 우선순위에 따라 그 값이 기본값을 대체한다.

## 신뢰하는 GitHub 실행

2026-09-14(Backend·Frontend)와 2026-09-23(AI 4개) GitHub API 조회 결과 여섯 저장소는 모두
`use_default: true`, `use_immutable_subject: true`다. 아래 `sub`를 각각의 Role에서 `StringEquals`로 허용하고,
`aud`도 `sts.amazonaws.com`과 정확히 일치해야 한다.

```text
Backend:  repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-backend@1348212870:ref:refs/heads/develop
Frontend: repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-FE@1344517410:ref:refs/heads/main
AI cuesheet:      repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-cuesheet@1375533793:ref:refs/heads/main
AI funding story: repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-AI-Funding-Story@1372645731:ref:refs/heads/main
AI copilot:       repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-Ai-copilot@1356653351:ref:refs/heads/main
AI highlight:     repo:KT-Cloud-Tech-Up-team6@316099892/Funddit-Ai-highlight@1363599970:ref:refs/heads/master
```

브랜치는 현재 각 저장소의 기본 브랜치를 기준으로 정했다. ID는 공개 식별자이며 토큰이나
Secret이 아니다. 조직명·저장소명·ID를 wildcard로 확장하지 않는다. 저장소 이전·이름 변경,
허용 브랜치 변경, OIDC subject 설정 변경은 코드와 연동 계약을 함께 검토한다.

아래 명령으로 설정만 조회할 수 있다. JWT/OIDC 토큰 자체를 출력할 필요가 없다.

```bash
gh api repos/KT-Cloud-Tech-Up-team6/Fundit-backend/actions/oidc/customization/sub
gh api repos/KT-Cloud-Tech-Up-team6/Fundit-FE/actions/oidc/customization/sub
gh api repos/KT-Cloud-Tech-Up-team6/Fundit-Ai-cuesheet/actions/oidc/customization/sub
gh api repos/KT-Cloud-Tech-Up-team6/Fundit-AI-Funding-Story/actions/oidc/customization/sub
gh api repos/KT-Cloud-Tech-Up-team6/Fundit-Ai-copilot/actions/oidc/customization/sub
gh api repos/KT-Cloud-Tech-Up-team6/Funddit-Ai-highlight/actions/oidc/customization/sub
```

일반 `pull_request`, 다른 브랜치, 태그, `environment:...` subject는 허용하지 않는다.
후속 이미지 Push job은 해당 브랜치의 `push`로 제한해야 한다. 브랜치 subject만으로 이벤트
종류가 항상 구분되는 것은 아니므로, `pull_request_target`에서 PR 코드를 checkout하거나
이 Role로 실행하지 않는다. `environment:`를 추가하면 subject가 바뀌므로 보호 규칙과
trust policy를 함께 협의해야 한다.

## ECR 권한

각 Role에는 `ecr-push` inline policy 하나를 연결한다.

- `ecr:GetAuthorizationToken`만 `Resource: "*"`이다. 저장소별 ARN 제한을 지원하지 않는
  로그인 API이며, 다른 저장소의 이미지에 쓰기 권한을 부여하는 것은 아니다.
- `BatchCheckLayerAvailability`, `BatchGetImage`, `InitiateLayerUpload`, `UploadLayerPart`,
  `CompleteLayerUpload`, `PutImage`는 자기 ECR 저장소 ARN 한 개에만 허용한다.
  Backend Role은 예외로 서비스별 저장소 전체에 허용하되 다른 CI Role이 소유한 저장소는 제외한다.
- ECR 생성·삭제, lifecycle 변경, IAM 관리, EC2 배포, GitOps 저장소 쓰기는 이 Role의 권한에 없다.
- ECR의 base image 또는 registry cache를 Pull하는 권한(`GetDownloadUrlForLayer`)은 포함하지
  않는다. 그런 빌드 방식이 필요하면 대상 저장소와 권한을 별도로 검토한다.

권한은 [AWS의 ECR Push 정책](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html)을
따른다. OIDC 형식과 Environment 동작은 [GitHub OIDC 문서](https://docs.github.com/en/actions/reference/security/oidc)를
기준으로 한다.

## 검증 및 AWS 담당자 인계

저장소 CI의 Terraform은 `1.10.5`이며, bootstrap lock 파일은 AWS provider `5.100.0`,
TLS provider `4.4.1`을 고정한다. 이 변경 때문에 도구나 provider 버전을 올리지 않는다.
Linux runner에서 `-lockfile=readonly`로 검사할 수 있도록 같은 버전의 공식 서명된
`linux_amd64` 패키지 체크섬을 lock 파일에 추가했다.

`.github/workflows/validate-ecr-ci.yml`은 관련 PR/main push와 수동 실행에서 아래 검사를
수행한다. `contents: read`만 사용하며 AWS Role Assume이나 실제 plan/apply를 실행하지 않는다.
기존 Terraform Plan/CD workflow는 그대로 유지한다.

AWS 계정에 연결하지 않는 검사:

```bash
terraform -chdir=terraform/envs/bootstrap fmt -check 04.ECRPushOIDC.tf outputs.tf tests/ecr_ci.tftest.hcl
terraform -chdir=terraform/envs/bootstrap init -backend=false -lockfile=readonly -input=false
terraform -chdir=terraform/envs/bootstrap validate
terraform -chdir=terraform/envs/bootstrap test -filter=tests/ecr_ci.tftest.hcl
```

검사에는 `.tf` 코드·lock 파일·테스트와 `modules/ecr`, `modules/s3`만 복사한 임시 디렉터리를
사용한다. 기존 `.terraform`, state, `.tfvars`, override 파일은 복사하지 않는다.
provider plugin 다운로드에는 인터넷이 필요하다. 테스트는 AWS/TLS mock provider와 모듈
override를 사용해 Role 신뢰 조건 및 저장소 간 쓰기 권한 분리를 검증한다.
테스트의 `command = apply`는 Terraform 1.10에서 mock ARN을 확정하기 위한 모의 실행이며,
실제 AWS에 리소스를 생성하는 `terraform apply`와 다르다.

AWS 담당자는 실제 상태를 사용하는 bootstrap plan에서 추가되는 CI Role과 inline policy를
확인한다. 기존 OIDC 공급자·ECR·Terraform Role에 예상하지 않은 변경이 있으면
원인을 확인한 뒤 반영한다. 실제 AWS 조회·apply·워크플로 재실행은 협업을 통해 진행한다.

반영 후 전달할 출력은 `ecr_ci_role_arns`와 `ecr_repository_urls` 두 항목이다.
원격 state 전체나 자격 증명 파일을 공유하지 않는다. 역할이 이미 수동으로 존재한다면
중복 생성하지 않도록 기존 관리 상태와 import 필요성을 먼저 확인한다.

이 단계의 코드/정책 검증은 실제 OIDC AssumeRole·Docker Push 성공을 의미하지 않는다.
App Repo를 연결할 때 허용 브랜치에서 임시 인증과 Push 성공, 잘못된 브랜치의 인증 거부,
다른 ECR 저장소로의 쓰기 거부를 확인한다.

## GitOps와 후속 작업

현재 [Fundit-GitOps Compose 구성](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-GitOps/tree/main/compose/dev)은
`GATEWAY_IMAGE`에 ECR URI를 받는다. 첫 Gateway 이미지는 기존 `fundit-backend`에
`gateway-sha-<백엔드의 40자리 커밋 SHA>`로 Push하고, 배포에는 가능하면 이미지 digest를 사용한다.
백엔드 여러 서비스가 같은 ECR을 사용하므로 서비스 접두사가 있어야 같은 커밋의 이미지가 충돌하지 않는다.

현재 ECR은 태그 덮어쓰기를 허용하며 lifecycle의 `sha-`, `dev-`, `commit-` 접두사는
`gateway-sha-`와 일치하지 않는다. 따라서 SHA 태그라는 이름만으로 불변성이나 자동 정리를
보장하지 않는다. 태그 불변성·서비스별 보존 정책은 기존 이미지를 다루는 AWS 담당자와
별도로 협의하며, 이번 인증 코드에서 변경하지 않는다.

다음 순서로 연결한다.

1. Infra: AWS 담당자 리뷰·적용 후 CI Role ARN/ECR URL 인계.
2. GitOps: 이미지 주소 갱신 검증, EC2 원격 실행 방식과 배포 사용자·디렉터리 계약 확정.
3. App Repo 후속 작업: Dockerfile 및 빌드·테스트, ECR Push job 연결.
4. App Repo → GitOps 이미지 갱신 → EC2 Pull/Compose/Health Check 통합 검증.

후속 App workflow는 `id-token: write`, `contents: read`와
`aws-actions/configure-aws-credentials`에 자신의 Role ARN/서울 리전을 지정한다.
빌드 성공 후에만 Push job을 실행한다. GitOps에 변경을 전달하는 GitHub 인증은 AWS OIDC와
별개이며, 이 변경에는 App Repo 코드나 GitHub Secrets/Variables 설정이 포함되지 않는다.
