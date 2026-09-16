# GitOps 개발 EC2 배포 인증

`Fundit-GitOps` Actions가 OIDC로 전용 IAM Role을 받아 SSM 문서로 Gateway 배포를 요청한다.
EC2의 배포 실행 파일은 검토된 GitOps `main` 커밋을 확인한 뒤 기존 `deploy-dev.sh`를 실행한다.
애플리케이션 이미지 빌드·ECR Push는 App Repo의 별도 역할이다.

## 관리 범위

| 담당 | 작업 |
|---|---|
| 조용빈 / Infra bootstrap | GitOps OIDC Role, 실행 정책, 전용 SSM Command 문서 |
| 조용빈 / GitOps | 수동 배포 Actions, 커밋 검증, 서버 실행 파일, Compose·health check |
| 이성규 / 개발 EC2 | Instance Profile, SSM·ECR Pull 권한, Agent, Docker, 사용자·디렉터리·실행 파일 설치 |

이 변경은 기존 GitHub OIDC 공급자를 참조하며 EC2, Instance Profile, 네트워크를 수정하지 않는다.
코드상 추가 대상은 Role·inline policy·SSM 문서 **3개**다. 이는 실제 Terraform Plan 결과가 아니다.
실제 state와 다른 팀 변경을 포함한 Plan은 적용 담당자가 별도로 확인한다.

## 인증과 실행 권한

Role 이름은 `fundit-dev-gitops-deploy-role`, 문서는 `fundit-dev-deploy-gateway`다.
신뢰 조건은 `StringEquals`만 사용한다.

```text
aud = sts.amazonaws.com
sub = repo:KT-Cloud-Tech-Up-team6@316099892/Fundit-GitOps@1359714048:environment:dev-deploy
```

Environment subject에는 브랜치가 들어가지 않는다. GitHub의 `dev-deploy` Environment에서
배포 브랜치를 `main`으로 제한하고 필수 승인자를 설정해야 한다.
워크플로의 `main` 확인도 함께 유지한다. [GitHub OIDC 설명](https://docs.github.com/en/actions/reference/security/oidc)

| API | 범위 |
|---|---|
| `ssm:SendCommand` | 위 전용 문서 ARN 하나 |
| `ssm:SendCommand` | 현재 AWS 계정·리전의 EC2 중 `Name=fundit-dev-app-ec2` **그리고** `Project=Fundit`인 대상 |
| `ssm:DescribeInstanceInformation`, `ssm:GetCommandInvocation` | `Resource=*`, `aws:RequestedRegion`으로 bootstrap 리전 제한 |

IAM의 태그 조건은 EC2 교체 시 권한 코드를 바꾸지 않도록 한다. GitOps는 Environment에 저장한
인스턴스 ID **한 개**를 명시해 보내며, Role은 그 대상의 두 태그까지 확인한다.
같은 태그를 가진 다른 EC2도 IAM 조건에는 맞으므로 대상 태그 관리는 AWS 담당자 권한에 둔다.
문서와 EC2의 `SendCommand` 권한은 별도 statement다. 문서에는 EC2 태그 조건을 걸지 않는다.
[AWS Run Command 태그 예제](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-setting-up.html)

상태 조회 API는 개별 리소스 ARN 제한을 지원하지 않아 `Resource=*`가 필요하다.
따라서 이 Role은 해당 리전의 다른 SSM 명령 결과도 조회할 수 있다. 비밀값을 Run Command 입력이나
표준 출력에 넣지 않고 서버 전용 런타임 파일에서 읽는다.
이 Role에 임의 `AWS-RunShellScript`, 문서 변경, EC2 시작·중지, IAM 변경, ECR Push 권한은 없다.
[AWS Systems Manager 권한 표](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ssm.html)

## SSM 문서와 서버 계약

문서는 스키마 `2.2`, Linux 전용이며 입력은 소문자 40자리 SHA인 `GitCommit` 하나뿐이다.
`ENV_VAR`로 전달된 `SSM_GitCommit`이 없으면 실패한다. 실행 단계 `deployGateway`의 제한 시간은 1,200초다.
사용자가 전달한 명령·URL·경로는 받지 않는다.

```sh
set -eu
test -n "${SSM_GitCommit:-}" || exit 1
exec runuser -u fundit-deploy -- /usr/local/libexec/fundit/deploy-dev-revision "$SSM_GitCommit"
```

SSM Agent는 `3.3.2746.0` 이상이어야 한다. 구형 Agent를 위해 문자열 치환 fallback을 추가하지 않는다.
[AWS ENV_VAR 요구 버전](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-troubleshooting.html)

성규님과 다음을 확인한 뒤 배포를 켠다.

- 개발 앱 EC2에 두 대상 태그, SSM용 Instance Profile, Backend ECR Pull 최소 권한을 적용한다.
- SSM Agent가 온라인이고 Linux에서 `runuser`를 사용할 수 있는지 확인한다.
- Docker·Compose·AWS CLI v2 및 GitOps 실행 파일의 필수 도구와 네트워크 접근을 준비한다.
  SSM, GitHub HTTPS, ECR API/Registry, 이미지 계층용 S3 연결이 필요하다.
- 검토된 GitOps 커밋에서 launcher를 가져와 위 고정 경로에 root 소유로 설치한다.
  배포 사용자가 launcher나 부모 디렉터리를 수정할 수 없게 한다.
- `fundit-deploy` 사용자가 Docker를 실행하고 배포 디렉터리를 쓸 수 있게 한다.
  Docker daemon 접근 권한은 호스트 관리 권한에 준하므로 `main` 리뷰·환경 승인으로 통제한다.
- `/var/lib/fundit/deploy`와 그 아래 `releases`를 준비하고 배포 사용자의 쓰기를 허용한다.
- 서버 전용 Gateway 런타임 파일 `/etc/fundit/dev/gateway.env`를 GitOps 문서의 소유권·권한으로 준비한다.
  비밀값을 GitHub 변수나 SSM 파라미터로 전달하지 않는다.

launcher는 실행마다 별도 릴리스 디렉터리에 GitOps를 가져오고 요청 SHA가 현재 `main`과
일치하는지 확인한다. 실행 중 `main`이 바뀌면 중단 후 새 커밋으로 재실행한다.
검토된 실행 파일의 설치·변경은 서버 준비 절차이며, 배포 문서가 자동으로 설치하지 않는다.

## 적용 및 활성화 순서

1. GitOps 워크플로와 launcher를 함께 리뷰한다. **Repository variable** `DEV_DEPLOY_ENABLED`는
   미설정 또는 `false`로 두고 아직 배포를 허용하지 않는다. Job 시작 조건에서 읽으므로
   Environment variable로만 등록하면 안 된다.
2. bootstrap의 실제 Plan을 팀에서 검토하고 적용 순서를 공유한다.
   기존 리소스의 의도하지 않은 변경이 없어야 한다. Apply는 한 명만 실행한다.
3. 적용 후 다음 outputs를 GitOps Environment 설정에 전달한다.
   - `gitops_dev_deploy_role_arn` → `DEV_DEPLOY_ROLE_ARN`
   - `gitops_dev_deploy_document_name` → 워크플로의 고정 문서명 `fundit-dev-deploy-gateway`와 일치 확인
   - `gitops_dev_deploy_document_version` → `DEV_DEPLOY_DOCUMENT_VERSION` (숫자로 고정)
4. AWS 담당자가 위 서버 준비를 완료하고 GitOps 담당자와 인스턴스 ID를 확인한다.
   그 ID 하나를 Environment variable `DEV_DEPLOY_INSTANCE_ID`에 등록한다.
5. GitOps `dev-deploy` Environment에 필수 승인자와 **main만** 배포 가능한 규칙을 저장한다.
   Role·인스턴스·문서 버전을 설정하고 실제 ECR 이미지와 런타임 설정도 준비한다.
6. 준비 상태 확인 후 `DEV_DEPLOY_ENABLED=true`로 바꾸고 검토된 `main`에서 수동 배포한다.
   SSM 종료 코드와 Gateway health check가 모두 성공해야 최초 배포 완료로 기록한다.

코드의 mock 테스트 성공은 실제 OIDC 인증·SSM 실행·ECR Pull·컨테이너 건강 상태를 보증하지 않는다.
bootstrap Role 신뢰 정책을 나중에 바꿀 때는 기존 Terraform 실행 Role의
`iam:UpdateAssumeRolePolicy` 권한과 관리자 선반영 절차도 확인한다.

## AWS 접근 없는 검증

```sh
cd terraform/envs/bootstrap
terraform fmt -check 04.ECRPushOIDC.tf 05.GitOpsDeployOIDC.tf outputs.tf tests/ecr_ci.tftest.hcl
terraform init -backend=false -lockfile=readonly -input=false
terraform validate -no-color
terraform test -filter=tests/ecr_ci.tftest.hcl -no-color
```

CI는 Terraform `1.10.5`를 사용한다. 테스트의 `command = apply`는 mock provider에만 적용되며
실제 AWS나 bootstrap state에 접근하지 않는다. 기존 ECR 경계와 GitOps 신뢰·SSM 대상·입력 경계를 함께 검증한다.
