---
type: Decision
title: vps-info PR 검증을 GitHub Actions로 옮기고 Jenkins는 main 배포만 한다
description: Jenkins multibranch의 PR 빌드를 vps-info 레포의 GitHub Actions workflow로 옮겨 PR 실패 로그를 GitHub 안에서 본다. main 배포는 그대로 Jenkins가 한다. ADR 0014의 PR 검증 부분을 대체한다.
tags: [ci, github-actions, jenkins, multibranch, branch-protection, github]
timestamp: 2026-11-20T00:00:00+09:00
---

# 상태

**확장.** 같은 날 main 배포도 [ADR 0019](/adr/0019-vps-info-cd-on-github-actions.md)로 Actions에 옮겼다. 아래의 "main 배포는 Jenkins" 부분은 그 ADR이 대체한다.

# 결정

`vps-info`의 PR 검증을 Jenkins multibranch PR 빌드에서 vps-info 레포의 `.github/workflows/ci.yml`로 옮긴다.
main 배포(`vps-info/main`의 Test → Decrypt → Deploy → ERD)는 그대로 Jenkins가 한다.
[ADR 0014](/adr/0014-multibranch-pr-ci.md)의 PR 검증 부분을 대체하고, main 배포 부분은 유지한다.

```txt
PR 생성·갱신 -> GitHub Actions CI (job `check:task`) -> 병합 필수 check
             -> notify job -> Mattermost (CI 성공·실패)
main 병합   -> GitHub webhook(push) -> Jenkins vps-info/main
             -> Test -> Decrypt -> Deploy -> ERD -> notifyMattermost(kind: 'CD')
```

- **workflow**: `pull_request`의 기본 checkout(대상 브랜치와 병합한 커밋, Jenkins `pr-merge`와 같다)을 `fetch-depth: 0`으로 받는다.
  Jenkins Test stage와 같은 방식으로 `docker build --target test` 후 `git archive HEAD`와 `.git`을 검사 컨테이너에 복사해
  `npm run check:task`를 돌린다. `CHECK_BASE`는 `origin/<github.base_ref>`다. 대상 브랜치를 main으로 제한하지 않는다(단계별 PR).
- **Jenkins Job**: `jobs.groovy`의 `vps-info` multibranch가 `includes('main')`과 `buildOriginPRMerge(false)`로 main만 발견한다.
  single `pipelineJob`으로 되돌리지 않는다. `BRANCH_NAME`이 비어 `when { branch 'main' }`이 항상 거짓이 되기 때문이다(ADR 0014).
- **필수 check**: main branch protection의 필수 check를 `continuous-integration/jenkins/pr-merge`에서 `check:task`로 바꾼다.
  설정은 GitHub에 있고 이 레포 코드에는 없다. workflow의 job `name`을 바꾸면 protection도 함께 바꿔야 한다.
- **webhook**: vps-info webhook 이벤트에서 `pull_request`를 빼고 `push`만 남긴다.
- **CI 알림**: workflow의 `notify` job이 레포 secret `MATTERMOST_WEBHOOK_URL`로 보낸다. secret이 없으면 건너뛴다.
  shared library `notifyMattermost()`에서 PR 빌드 전용 경로(`CHANGE_*` 필드, `kind == 'CI'` 문구)를 지운다.
  main 빌드 알림 payload는 바뀌지 않는다.

# 배경

PR이 실패하면 GitHub check의 Details가 Jenkins 빌드 페이지로 연결되어, 로그를 보려면 Jenkins로 넘어가 로그인해야 했다.
Jenkins는 2026-08-22 실측으로 VPS 사용 메모리 2.0GB 중 1.0GB를 차지하는 가장 큰 소비자이고([ADR 0006](/adr/0006-jenkins-builds-on-vps.md)),
ADR 0006이 Jenkins를 둔 이유였던 학습 목적은 어느 정도 달성했다고 판단했다.
CD 이전(Actions 빌드 + GHCR + SSH 배포)과 Jenkins 제거는 이후 별도 결정으로 다루고, 이번에는 범위가 작은 CI부터 옮긴다.

# 이유

- **로그가 PR 화면에 있다.** 실패 로그, 재실행, 실패 step이 PR의 Checks 탭 안에 있다.
- **PR 검증이 외부 webhook 전달에 의존하지 않는다.** [ADR 0015](/adr/0015-multibranch-periodic-scan.md)의 PR #3 사례처럼
  `pull_request` webhook이 연결 단계에서 실패해 필수 check가 `Expected`에 멈추는 일이 Actions에서는 생기지 않는다.
- **VPS가 PR 빌드를 하지 않는다.** test image 빌드(`npm ci` 포함)가 VPS 밖에서 돌고, `numExecutors: 1`을 PR 빌드가 점유해
  main 배포가 대기하는 일도 없어진다.
- **fork PR을 막을 이유가 사라진다.** GitHub-hosted runner에는 VPS의 docker.sock이 없다. fork PR에는 secret이 전달되지 않으므로
  알림만 빠진다.

# 결과

- PR 빌드 이력은 Jenkins에서 Actions로 이어지지 않는다.
- PR에서 JUnit 집계 화면이 사라진다. 실패한 테스트는 Actions 로그에서 본다. main 빌드의 `junit`은 남는다.
- CI 알림이 단순해진다. 실패 단계·실패 테스트·로그 꼬리 대신 Actions run 링크를 싣는다. 새 push로 취소된 실행은 알리지 않는다.
- hosted runner는 빌드 캐시가 없어 매 PR마다 test image를 처음부터 빌드한다. 느려지면 buildx `type=gha` 캐시를 붙인다.
- Jenkins main 빌드의 Test는 배포 직전 재검증으로 남는다. `CHECK_BASE`는 `origin/main`으로 고정한다.
- [ADR 0015](/adr/0015-multibranch-periodic-scan.md)의 15분 스캔은 놓친 main push를 보완하는 용도로만 남는다.
- **적용 순서**. 순서를 바꾸면 PR이 `Expected` 상태로 병합이 막히거나 검증 없이 병합될 수 있다.
  1. vps-info에 `ci.yml` PR을 올린다. 이 PR에는 Jenkins `pr-merge`와 Actions `check:task`가 둘 다 뜬다.
  2. Actions check가 한 번 보고된 뒤 branch protection의 필수 check를 `check:task`로 바꾼다.
  3. vps-info PR을 병합한다(Jenkins main 빌드가 배포한다).
  4. vps-infra의 `jobs.groovy` 변경을 main에 push한다. vps-infra 파이프라인의 JCasC reload로 PR job이 사라진다.
  5. vps-info webhook에서 `pull_request` 이벤트를 뺀다.

# 관련 개념

- [vps-info는 multibranch job으로 PR을 검증하고 main에서만 배포한다](/adr/0014-multibranch-pr-ci.md)
- [vps-info multibranch가 15분마다 스캔해 유실된 webhook을 보완한다](/adr/0015-multibranch-periodic-scan.md)
- [빌드 결과를 Shared Library로 Mattermost에 알린다](/adr/0012-mattermost-build-notification.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
