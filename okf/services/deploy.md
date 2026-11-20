---
type: Deployment Service
title: 배포 (GitHub Actions + SSH forced command)
description: 각 레포의 GitHub Actions가 forced command로 묶인 key로 VPS의 배포 스크립트에 SHA만 넘긴다. vps-infra는 scripts/ci-deploy.sh가 배포한다.
tags: [deployment, github-actions, ssh, sops, docker-compose]
timestamp: 2026-11-20T00:00:00+09:00
---

# 개요

VPS 배포는 프로젝트마다 자기 레포의 GitHub Actions가 맡는다. VPS에는 배포용 상주 프로세스가 없다.
Actions는 `authorized_keys`의 forced command로 묶인 key로 접속해 SHA(와 옵션)만 넘기고, 배포 순서는 VPS의 스크립트에 있다.
Jenkins는 [ADR 0021](/adr/0021-remove-jenkins.md)로 걷어냈다.

| 레포 | workflow | VPS 진입점 | 결정 |
|------|----------|-----------|------|
| vps-infra | `.github/workflows/validate.yml` | `~/app/vps-infra/scripts/ci-deploy.sh "<sha> <target>"` | [ADR 0020](/adr/0020-infra-cd-on-github-actions.md) |
| vps-info | vps-info `.github/workflows/ci.yml` | `~/app/vps-info/scripts/deploy.sh "<sha> [erd]"` | [ADR 0019](/adr/0019-vps-info-cd-on-github-actions.md) |

vps-info 쪽 상세는 [vps-info](/services/vps-info.md)에 있다. 이 문서는 vps-infra 배포를 다룬다.

# 흐름 (vps-infra)

```txt
main push -> validate job(compose·nginx 문법, seam 1·3, SOPS 암호화 확인)
-> deploy job: ssh kkh@187.77.114.68 "<sha> <target>"  (secret VPS_DEPLOY_KEY)
   -> authorized_keys: command="/home/kkh/app/vps-infra/scripts/ci-deploy.sh",restrict
      -> flock /tmp/vps-deploy.lock
      -> git checkout <sha> (origin/main 이력의 커밋만)
      -> 대상 판정: auto면 .deploy-state/last-successful-sha부터 scripts/select-target.sh, 그 외 all|portal|observability
      -> docker compose run --rm --no-deps -T tools ./scripts/secrets.sh decrypt  (ENV_NAME=prod)
      -> scripts/deploy.sh <target>
      -> HEALTHCHECK_CONNECT_HOST=127.0.0.1 scripts/healthcheck.sh
      -> .deploy-state/last-successful-sha 기록
-> notify job: Mattermost (secret MATTERMOST_WEBHOOK_URL)
```

- `/tmp/vps-deploy.lock`은 vps-info 배포 스크립트와 같은 lock이다. VPS에서 배포는 한 번에 하나만 돈다.
- `.deploy-state/last-successful-sha`는 VPS checkout의 runtime state라 Git에 커밋하지 않는다. healthcheck가 성공한 경우에만 갱신한다.
  파일이 없거나 이번 SHA의 조상이 아니면 전체(`all`)를 배포한다.
- VPS의 `.env`는 매 배포마다 `secrets/env.prod.sops.env`에서 다시 만들어진다. `.env`를 직접 고치면 다음 배포에서 덮어써지므로 값은 SOPS 파일에서 바꾼다.
- 복호화 key는 호스트의 `~/.config/sops/age/keys.txt` 하나다. `sops`는 호스트에 설치하지 않고 `tools` 이미지로 실행한다.
- healthcheck는 공개 DNS 대신 호스트의 nginx(443)에 `127.0.0.1`로 붙는다.
- 배포 뒤 VPS checkout은 detached HEAD다. 배포된 커밋은 `git log -1`로 본다.

# 수동 재배포와 롤백

- Actions에서 `Validate infra config` workflow를 main으로 `workflow_dispatch` 실행한다. `target` 입력은 `auto|all|portal|observability`다.
- VPS에서 직접: `~/app/vps-infra/scripts/ci-deploy.sh <sha> all`. 롤백은 이전 main SHA를 넘긴다.

# 배포 key

- `~/.ssh/authorized_keys`의 `command="/home/kkh/app/vps-infra/scripts/ci-deploy.sh",restrict` 한 줄(comment `vps-infra-deploy`)이다.
  private key는 레포 secret `VPS_DEPLOY_KEY`에만 있다. key를 바꿀 때는 두 곳을 함께 바꾼다.
- workflow는 VPS host key를 `validate.yml`의 `VPS_HOST_KEY`로 고정한다. VPS를 다시 만들면 그 값도 바꿔야 배포된다.
- SSH로 들어온 문자열은 셸로 해석하지 않는다. `ci-deploy.sh`가 40자 SHA와 허용된 target만 받는다.

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
