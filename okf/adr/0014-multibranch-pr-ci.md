---
type: Decision
title: vps-info는 multibranch job으로 PR을 검증하고 main에서만 배포한다
description: GitHub PR마다 Jenkins가 Test를 돌려 commit status로 보고하고, 브랜치 보호의 필수 check로 병합을 막는다. 배포는 main 빌드에서만 한다.
tags: [jenkins, multibranch, ci, branch-protection, github]
timestamp: 2026-10-01T00:00:00+09:00
---

# 결정

`vps-info` job을 단일 `pipelineJob`(`*/main`만 빌드)에서 `multibranchPipelineJob`(github-branch-source)으로 바꾼다.

```txt
PR 생성·갱신 -> GitHub webhook(pull_request) -> vps-info/PR-<n>
-> 대상 브랜치와 병합한 결과로 Test만 실행 -> GitHub commit status(Jenkins) -> 필수 check
main 병합 -> GitHub webhook(push) -> vps-info/main
-> Test -> Decrypt -> Deploy -> ERD
```

- `Jenkinsfile`은 하나다. Decrypt, Deploy, ERD stage에 `when { branch 'main' }`을 둬 PR 빌드가 운영 secret을 읽거나 배포하지 못하게 한다.
- main의 Test는 남긴다. squash merge면 main 커밋 SHA가 PR에서 테스트한 SHA와 다르고, 배포 직전 한 번 더 검증하는 비용이 작다.
- GitHub 브랜치 보호(main): PR 필수, Jenkins check 필수, 브랜치가 최신이어야 병합. 설정은 GitHub UI·`gh api`에 있고 이 레포 코드에는 없다.
- fork PR은 발견하지 않는다(`gitHubForkDiscovery` 없음). Jenkins가 docker.sock을 써서 외부 코드 실행은 호스트 권한과 같다.
- 알림은 CI(PR 빌드)와 CD(main 빌드)의 성공·실패만 보낸다([ADR 0012](/adr/0012-mattermost-build-notification.md)). PR 생성·승인 알림은 두지 않는다.

# 이유

- 단일 job은 PR 브랜치를 빌드 대상으로 삼지 못하고, 결과를 PR에 보고하지도 못한다. 별도 CI job을 직접 만들면 PR 발견,
  병합 커밋 checkout, status 보고, fork 신뢰 판단을 스크립트로 구현해야 하고 결국 plugin이 하나 더 필요하다.
- `github-branch-source`는 이를 모두 제공하고, 추가하는 plugin은 하나다.

# 결과

- `plugins.txt`에 `github-branch-source`가 추가되어 **Jenkins 이미지 재빌드(SSH)가 필요하다**. JCasC reload만으로는 plugin이 설치되지 않는다.
- GitHub webhook 이벤트는 push만이었다. `pull_request`를 추가해야 PR 빌드가 바로 시작된다.
- multibranch는 브랜치마다 빌드 번호가 따로 오른다. 그래서 Jenkinsfile의 컨테이너 이름에 `JOB_BASE_NAME`을 넣는다.
- 기존 단일 job의 빌드 이력은 새 job으로 이어지지 않는다.
- 필수 check 이름은 첫 PR 빌드가 status를 보고한 뒤에야 GitHub에서 고를 수 있다.
- 로컬 Jenkins는 GitHub를 직접 조회하므로 push하지 않은 커밋을 시험하던 `VPS_INFO_SCM_URL` 방식이 vps-info에서는 사라진다.
- 이 변경 전에 vps-info `Jenkinsfile`을 main에 넣으면 안 된다. 단일 job에서는 `BRANCH_NAME`이 비어 `when { branch 'main' }`이 항상 거짓이라 배포 stage가 건너뛰어지고 빌드는 성공으로 표시된다.

# 관련 개념

- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [빌드 결과를 Shared Library로 Mattermost에 알린다](/adr/0012-mattermost-build-notification.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
