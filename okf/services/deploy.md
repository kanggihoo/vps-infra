---
type: Deployment Service
title: 배포 (GitHub Actions + SSH forced command)
description: 각 레포의 GitHub Actions가 forced command로 묶인 key로 VPS의 배포 스크립트에 SHA와 배포 옵션을 넘긴다. vps-infra는 scripts/ci-deploy.sh가 배포한다.
tags: [deployment, github-actions, ssh, sops, docker-compose]
timestamp: 2026-11-22T00:00:00+09:00
---

# 개요

VPS 배포는 프로젝트마다 자기 레포의 GitHub Actions가 맡는다. VPS에는 배포용 상주 프로세스가 없다.
Actions는 `authorized_keys`의 forced command로 묶인 key로 접속해 SHA(와 옵션)만 넘기고, 배포 순서는 VPS의 스크립트에 있다.
Jenkins는 [ADR 0021](/adr/0021-remove-jenkins.md)로 걷어냈다.

| 레포 | workflow | VPS 진입점 | 결정 |
|------|----------|-----------|------|
| vps-infra | `.github/workflows/pipeline.yml` | `~/app/vps-infra/scripts/ci-deploy.sh "<sha> <target> [digest|reuse]"` | [ADR 0020](/adr/0020-infra-cd-on-github-actions.md) |
| vps-info | vps-info `.github/workflows/ci.yml` | `~/app/vps-info/scripts/deploy.sh "<sha> [erd]"` | [ADR 0019](/adr/0019-vps-info-cd-on-github-actions.md) |

vps-info 쪽 상세는 [vps-info](/services/vps-info.md)에 있다. 이 문서는 vps-infra 배포를 다룬다.

# 흐름 (vps-infra)

```txt
PR, main push, main 수동 실행 → ci.yml (설정·SOPS, Gitleaks, Portal 빌드) → gate
PR 종료
main push → publish.yml (GHCR Portal SHA 태그 게시, digest 출력) → cd.yml → Mattermost
main 수동 실행 → cd.yml (입력 digest 또는 기존 적용 기록) → Mattermost
```

- CI에서 Gitleaks 8.30.1로 도입된 커밋을 검사한다. base를 확인할 수 없으면 도달 가능한 이력을 검사한다. 로컬의 Lefthook은 같은 버전으로 staged 변경을 검사한다. 두 경로 모두 검출값을 가린다.
- 게시 job에 `packages: write`를 준다. `ghcr.io/kanggihoo/vps-infra-portal:<full-sha>`로 게시하고 Actions 요약에 commit SHA와 digest를 함께 기록한다.
- VPS는 `/tmp/vps-deploy.lock`을 vps-info와 공유한다. main 이력의 SHA로 checkout하고 `auto`는 마지막 성공 범위부터 누적 diff로 대상을 계산한다. 상태가 없거나 이전 성공 SHA가 조상이 아니면 `all`을 적용한다.
- VPS는 고정된 Portal repository에서 digest를 pull하고 OCI revision을 검증한다. `tools`를 빌드한 뒤 SOPS에서 `.env`와 secret을 복호화한다. Portal은 pull한 이미지로 기동하고 nginx를 거친 `/api/version`이 요청 SHA인지 검사한다.
- healthcheck 성공 후 `.deploy-state/portal`에 적용된 Portal SHA와 digest를 기록한다. `observability` 배포에서는 기존 Portal을 확인하며 그 기록을 유지한다. `.deploy-state/last-successful-sha`는 `auto` 또는 `all` 적용 뒤 갱신한다.
- checkout은 detached HEAD다. 현재 checkout SHA, 인프라의 성공 범위, 실행 중인 Portal은 각각 `git log -1`, `.deploy-state/last-successful-sha`, `.deploy-state/portal`로 확인한다.

# GHCR 배포 전환

1. `PORTAL_GHCR_DEPLOY`를 설정하지 않은 상태로 병합한다. main에서 Portal 게시와 기존 2인자 SSH 배포가 성공하면 VPS checkout에 새 parser가 들어간다.
2. GHCR 가시성을 결정하고 VPS의 배포 계정에서 Actions 요약의 digest로 pull을 확인한다. public이면 로그인 없이 확인한다. private이면 같은 계정에 패키지 읽기 권한이 있는 자격 증명을 설정한다. 이미지 플랫폼도 VPS와 맞는지 확인한다.
3. GitHub Actions repository variable `PORTAL_GHCR_DEPLOY=true`를 설정한다. 첫 검증은 main의 `Infra pipeline`을 수동 실행하고 `target=all`, 해당 main SHA의 게시 digest를 전달한다. 다음 main push부터 게시 digest가 자동으로 전달된다.
4. GitHub에서 main PR 보호가 필요하면 PR 실행에 표시된 CI의 `gate` check를 ruleset에서 필수로 지정한다. 보호 정책을 적용한 뒤 검사 실패 PR에서 병합이 차단되는지 확인한다.

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
