# bootstrap IAM 신뢰 정책 변경 절차

이 문서는 `terraform/envs/bootstrap`의 IAM Role 신뢰 정책(AssumeRolePolicy)을 바꿀 때
거치는 수동 절차를 다룬다. [Issue #61](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/61)
배경이다.

## 배경

`fundit-terraform-ci-role`은 권한 상승을 막기 위해 `iam:UpdateAssumeRolePolicy`를 갖지
않는다(`terraform/envs/bootstrap/03.OIDC.tf:102-121`, `ManageProjectRoles` Statement에
이 액션이 없다). 그래서 bootstrap 레이어에서 신뢰 정책을 바꾸는 PR을 병합하면, GitHub
Actions CD가 자동으로 apply할 때 `AccessDenied`가 난다.

## 절차

신뢰 정책 변경이 포함된 PR은 아래 순서로 진행한다.

1. 관리자 프로필(`team6-infra`)로 로컬에서 `terraform/envs/bootstrap`을 직접 `apply`한다.
2. `aws iam get-role --role-name <역할명> --profile team6-infra`로 신뢰 정책이 코드와
   일치하는지 확인한다.
3. PR 브랜치의 CI plan이 `No changes. Your infrastructure matches the configuration.`
   (0 add, 0 change, 0 destroy)로 나오는지 확인한 뒤 병합한다.

## 점검 체크리스트

- [ ] 로컬 apply 전에 `aws sts get-caller-identity --profile team6-infra`로 계정 ID(`899957568205`)를 확인했다
- [ ] 로컬 apply 후 `aws iam get-role`로 신뢰 정책이 코드와 일치함을 확인했다
- [ ] PR의 CI plan이 0 add / 0 change / 0 destroy로 나왔다
- [ ] 병합 후 CD가 실행되어도 추가로 바뀌는 게 없는지 확인했다(신뢰 정책이 이미 반영돼 있으므로)

## 중장기 검토

PR Plan 전용 Role(ReadOnly)과 승인 기반 Apply Role을 분리하는 방안이 검토 항목으로
남아 있다. 결정된 내용은 없다.

## 참고

- [Issue #61](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/61)
- [PR #58](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/pull/58): CD 승인 게이트(dev-apply) 도입에 따른 OIDC 신뢰 조건 추가
- [Issue #54](https://github.com/KT-Cloud-Tech-Up-team6/Fundit-Infra/issues/54): CD 승인 게이트 도입에 따른 OIDC AssumeRole 권한 오류 해결
