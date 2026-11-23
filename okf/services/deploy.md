---
type: Deployment Service
title: 배포 (GitHub Actions + SSH forced command)
description: 각 레포의 GitHub Actions가 forced command로 묶인 key로 VPS의 배포 스크립트에 SHA와 배포 옵션을 넘긴다. vps-infra는 scripts/ci-deploy.sh가 배포한다.
tags: [deployment, github-actions, ssh, sops, docker-compose]
timestamp: 2026-11-23T00:00:00+09:00
---

# 개요

VPS 배포는 프로젝트마다 자기 레포의 GitHub Actions가 맡는다. VPS에는 배포용 상주 프로세스가 없다.
Actions는 `authorized_keys`의 forced command로 묶인 key로 접속해 SHA(와 옵션)만 넘기고, 배포 순서는 VPS의 스크립트에 있다.
Jenkins는 [ADR 0021](/adr/0021-remove-jenkins.md)로 걷어냈다.

| 레포 | workflow | VPS 진입점 | 결정 |
|------|----------|-----------|------|
| vps-infra | `.github/workflows/pr.yml`, `main.yml`, `redeploy.yml` | `~/app/vps-infra/scripts/ci-deploy.sh "<sha> <target> [digest|reuse]"` | [ADR 0020](/adr/0020-infra-cd-on-github-actions.md) |
| vps-info | vps-info `.github/workflows/ci.yml` | `~/app/vps-info/scripts/deploy.sh "<sha> [erd]"` | [ADR 0019](/adr/0019-vps-info-cd-on-github-actions.md) |

vps-info 쪽 상세는 [vps-info](/services/vps-info.md)에 있다. 이 문서는 vps-infra 배포를 다룬다.

# 흐름 (vps-infra)

```txt
PR          → pr.yml (Infra PR)          → ci.yml → gate
main push   → main.yml (Infra deploy)    → ci.yml → gate → publish.yml (GHCR Portal SHA 태그 게시, digest 출력) → cd.yml → Mattermost
main 수동 실행 → redeploy.yml (Infra redeploy) → cd.yml (입력 digest 또는 기존 적용 기록) → Mattermost
```

workflow는 trigger마다 파일 하나로 나뉜다. 각 파일은 분기 없이 위에서 아래로 실행된다. `ci.yml`, `publish.yml`, `cd.yml`은 이 세 파일이 호출하는 reusable workflow다.

- `main.yml`은 PR에서 통과한 CI를 merge 결과 commit에 다시 실행한다. ruleset의 strict check가 PR이 최신 main을 포함하도록 강제하지만, main 쪽 CI는 검증되지 않은 tree가 VPS로 가는 것을 한 번 더 막는다.
- `redeploy.yml`은 CI를 실행하지 않는다. 이미 main에서 검증된 SHA를 다시 적용하기 때문이다. 수동 실행은 아무 branch에서나 할 수 있으므로 `cd.yml`의 `github.ref == 'refs/heads/main'` guard가 main 외 branch의 배포를 막는다.
- `main.yml`과 `redeploy.yml`은 concurrency group `infra-deploy`를 공유하고 진행 중인 실행을 취소하지 않는다. 배포 중에 실행이 두 개 이상 쌓이면 GitHub는 가장 최근 대기 실행만 남긴다. `auto`가 마지막 성공 SHA부터 누적 diff로 대상을 계산하므로 건너뛴 배포의 변경도 다음 배포에 포함된다.
- `pr.yml`은 PR 번호별 group에서 이전 실행을 취소한다.
- Mattermost 알림은 두 배포 workflow가 `scripts/notify-mattermost.sh`를 호출한다. 커밋 메시지 같은 사용자 입력은 env로만 넘긴다.

- CI에서 Gitleaks 8.30.1로 도입된 커밋을 검사한다. base를 확인할 수 없으면 도달 가능한 이력을 검사한다. 로컬의 Lefthook은 같은 버전으로 staged 변경을 검사한다. 두 경로 모두 검출값을 가린다.
- 게시 job에 `packages: write`를 준다. `ghcr.io/kanggihoo/vps-infra-portal:<full-sha>`로 게시하고 Actions 요약에 commit SHA와 digest를 함께 기록한다.
- VPS는 `/tmp/vps-deploy.lock`을 vps-info와 공유한다. main 이력의 SHA로 checkout하고 `auto`는 마지막 성공 범위부터 누적 diff로 대상을 계산한다. 상태가 없거나 이전 성공 SHA가 조상이 아니면 `all`을 적용한다.
- VPS는 고정된 Portal repository에서 digest를 pull하고 OCI revision을 검증한다. `tools`를 빌드한 뒤 SOPS에서 `.env`와 secret을 복호화한다. Portal은 pull한 이미지로 기동하고 nginx를 거친 `/api/version`이 요청 SHA인지 검사한다.
- healthcheck 성공 후 `.deploy-state/portal`에 적용된 Portal SHA와 digest를 기록한다. `observability` 배포에서는 기존 Portal을 확인하며 그 기록을 유지한다. `.deploy-state/last-successful-sha`는 `auto` 또는 `all` 적용 뒤 갱신한다.
- checkout은 detached HEAD다. 현재 checkout SHA, 인프라의 성공 범위, 실행 중인 Portal은 각각 `git log -1`, `.deploy-state/last-successful-sha`, `.deploy-state/portal`로 확인한다.

# GHCR 배포 전환

1. `PORTAL_GHCR_DEPLOY`를 설정하지 않은 상태로 병합한다. main에서 Portal 게시와 기존 2인자 SSH 배포가 성공하면 VPS checkout에 새 parser가 들어간다.
2. GHCR 가시성을 결정하고 VPS의 배포 계정에서 Actions 요약의 digest로 pull을 확인한다. public이면 로그인 없이 확인한다. private이면 같은 계정에 패키지 읽기 권한이 있는 자격 증명을 설정한다. 이미지 플랫폼도 VPS와 맞는지 확인한다.
3. GitHub Actions repository variable `PORTAL_GHCR_DEPLOY=true`를 설정한다. 첫 검증은 main에서 `Infra redeploy`를 수동 실행하고 `target=all`, 해당 main SHA의 게시 digest를 전달한다. 다음 main push부터 게시 digest가 자동으로 전달된다.

# main 보호 (ruleset과 merge 설정)

main ruleset과 repository merge 설정은 코드로 관리한다. ruleset 정의는 `.github/rulesets/main.json`에 있고, `scripts/apply-github-settings.sh`가 ruleset과 repository 설정을 함께 적용한다.
GitHub UI에서 바꾼 값은 스크립트를 다시 실행하면 덮어써진다.

- PR 필수, 승인 수 0. 혼자 쓰는 repo라 자기 PR을 승인할 수 없으므로 1 이상이면 merge가 막힌다.
- `ci / gate` 필수(`integration_id` 15368, GitHub Actions). `strict_required_status_checks_policy: true`라서 다른 PR이 먼저 merge되면 남은 PR은 "Update branch" 뒤 CI를 다시 통과해야 merge할 수 있다. 사용자가 누른 Update branch는 `pull_request` event를 발생시켜 `pr.yml`이 자동으로 다시 돈다.
- squash merge만 허용하고 force push와 삭제를 막는다.
- repository admin(`RepositoryRole` 5)은 `pull_request` 모드로만 우회한다. 실패한 PR을 강제 merge할 수는 있지만 직접 push는 admin도 막힌다.
- repository 설정: merge commit과 rebase merge를 끄고, squash 메시지는 `PR_TITLE`/`PR_BODY`, merge 후 head branch 삭제, Update branch 버튼 항상 표시.

conflict가 있는 PR은 ruleset과 상관없이 GitHub가 merge를 막는다. PR 제목·branch 규칙은 `CONTRIBUTING.md`에 있다.

`pr.yml`의 job id `ci`가 check 이름 `ci / gate`를 만든다. job id나 `ci.yml`의 `gate` job 이름을 바꾸면 ruleset의 필수 check도 같이 바꿔야 한다. 그렇지 않으면 모든 PR이 영원히 대기한다.

# 수동 재배포와 롤백

- Actions 수동 실행은 실행 당시 main SHA를 대상으로 한다. SHA에 해당하는 게시 digest를 입력하거나, 그 SHA가 현재 Portal 적용 기록과 일치하면 빈 입력으로 digest를 재사용한다. 실제 재적용은 `target=portal`이나 `all`로 실행한다. 이미 배포한 같은 SHA에 대한 `auto`는 기본적으로 healthcheck만 한다.
- 호환되는 이전 SHA의 전체 롤백은 VPS에서 `~/app/vps-infra/scripts/ci-deploy.sh <sha> all <digest>`를 실행한다. 이전 실행의 SHA/digest 쌍과 GHCR 이미지가 보존돼 있어야 한다. Actions 요약은 run 보관 기간의 영향을 받으므로 원하는 롤백 기간에 맞춰 쌍을 보관한다.
- 같은 SHA 태그가 이미 있으면 publish는 중단한다. 기존 게시 요약에서 digest를 확인해 수동 배포한다. 실패한 job만 재실행하는 경우 게시 결과가 배포 job에 전달되는지는 첫 전환 검증에서 확인한다.
- 전환 이전 상태로 복구해야 하면 `PORTAL_GHCR_DEPLOY`를 끄고 VPS에서 기존 2인자 명령으로 해당 SHA를 전체 재배포한다. 전환을 다시 시작할 때 먼저 새 parser를 포함하는 커밋을 배포한다.

# 배포 key

- `~/.ssh/authorized_keys`의 `command="/home/kkh/app/vps-infra/scripts/ci-deploy.sh",restrict` 한 줄(comment `vps-infra-deploy`)이다.
  private key는 레포 secret `VPS_DEPLOY_KEY`에만 있다. key를 바꿀 때는 두 곳을 함께 바꾼다.
- workflow는 VPS host key를 `cd.yml`의 `VPS_HOST_KEY`로 고정한다. VPS를 다시 만들면 그 값도 바꿔야 배포된다.
- SSH로 들어온 문자열은 셸로 해석하지 않는다. `ci-deploy.sh`가 40자 SHA, 허용된 target, 선택적 digest 또는 `reuse`만 받는다.

# 주의

- **배포 스크립트 변경은 다음 배포부터 적용된다.** VPS에 이미 있는 `ci-deploy.sh`(vps-info는 `scripts/deploy.sh`)가 먼저 실행돼
  새 커밋을 checkout하기 때문이다. 첫 전환 때도 같은 이유로 VPS에서 `git pull`을 한 번 손으로 했다.
- 배포 로그는 Actions run에 있다. 컨테이너 로그는 [관측 스택](/services/observability.md)의 Loki에서 본다.

# 관련 개념

- [vps-infra 배포를 GitHub Actions + SSH forced command로 옮긴다](/adr/0020-infra-cd-on-github-actions.md)
- [Jenkins를 VPS에서 걷어낸다](/adr/0021-remove-jenkins.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [과거 GitHub Actions SSH 배포](/services/github-actions-deploy.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
