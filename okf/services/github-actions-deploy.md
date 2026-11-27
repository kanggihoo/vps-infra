---
type: Deployment Service
title: 과거 GitHub Actions SSH 배포
description: 폐기된 과거 SSH 배포 경로를 기록한다. 현재 배포는 services/deploy.md에 있다.
tags: [deployment, github-actions, ssh, docker-compose]
timestamp: 2026-08-25T00:00:00+09:00
---

# 상태

**이 SSH 배포 경로는 폐기.** 이 문서의 SSH 배포 흐름(`/opt/vps-infra`, 제한 없는 `VPS_SSH_KEY`)은
역사 기록이며 현재 운영 절차가 아니다. 2026-11-20부터 `.github/workflows/validate.yml`이 검증 뒤 다시 배포하지만,
forced command로 묶인 key로 `scripts/ci-deploy.sh`만 부르는 다른 방식이다. 현재 흐름은 [배포](/services/deploy.md)에 있다.

# 개요

Jenkins migration 전 GitHub Actions가 `main` 변경을 자동 배포했다. 이후 Jenkins가 배포를 맡았다가
[ADR 0020](../../docs/adr/0020-infra-cd-on-github-actions.md)·[ADR 0021](../../docs/adr/0021-remove-jenkins.md)로 다시 Actions로 돌아왔다.
아래 SSH 흐름은 과거 구현 기록이다.

이 서비스는 [SSH git-pull 배포 결정](../../docs/adr/0001-ssh-git-pull-deployment.md)을 구현한다.

# 과거 트리거

```yaml
on:
  push:
    branches: [main]
```

현재 workflow의 트리거와 수동 재배포는 [배포](/services/deploy.md)를 본다.

# 흐름

기본 흐름은 push diff를 확인한 뒤 배포 범위를 고른다.

```txt
main 변경
-> GitHub Actions 실행
-> VPS에 kkh 사용자로 SSH 접속
-> cd /opt/vps-infra
-> git diff --name-only <before> <sha>
-> 변경 파일이 모두 portal/** 이면 target=portal
-> 그 외 변경이 있으면 target=all
-> git pull origin main
-> ./scripts/deploy.sh <target>
```

`target=portal`은 포털 service만 rebuild/recreate한다.

```txt
docker compose up -d --build --no-deps portal
docker compose ps portal
```

`target=all`은 전체 Compose stack을 적용하고 PostgreSQL/Redis local check까지 실행한다.

```txt
docker compose config
docker compose pull --ignore-buildable
docker compose up -d --build --wait
docker compose ps
postgres pg_isready
redis ping
```

# Secrets

| Secret | 용도 |
|--------|------|
| `VPS_HOST` | VPS public IP. 현재 `187.77.114.68`. |
| `VPS_USER` | SSH 사용자. 현재 `kkh`. |
| `VPS_PORT` | SSH 포트. 보통 `22`. |
| `VPS_SSH_KEY` | GitHub Actions 전용 배포 private key. 다시 쓰지 않는다(현재는 `VPS_DEPLOY_KEY`). |

# 관계

이 workflow는 [nginx](/services/nginx.md), [PostgreSQL](/services/postgresql.md),
[Redis](/services/redis.md), [whoami](/services/whoami.md), [공용 인프라 포털](/services/portal.md)을 시작하고 갱신한다.
