---
type: Deployment Service
title: GitHub Actions 배포
description: 과거 main 변경 시 GitHub Actions가 SSH로 VPS에 접속해 배포하던 방식.
tags: [deployment, github-actions, ssh, docker-compose]
timestamp: 2026-07-03T00:00:00+09:00
---

# 상태

이 방식은 Jenkins migration 이후 자동 배포 경로로 사용하지 않는다. workflow는
수동 rollback 또는 emergency deployment 용도로만 남겨둔다.

# 개요

Jenkins migration 전 GitHub Actions가 `main` 변경을 자동 배포했다. 현재는
자동 트리거가 제거되었고, workflow를 수동 실행하는 비상 경로로만 유지한다.
workflow는 Hostinger VPS에 `kkh` 사용자로 SSH 접속하고, `/opt/vps-infra`
repository를 갱신한 뒤 Docker Compose를 적용한다.

이 서비스는 [SSH git-pull 배포 결정](/decisions/ssh-git-pull-deployment.md)을 구현한다.

# 과거 트리거

```yaml
on:
  push:
    branches: [main]
```

현재 workflow는 `workflow_dispatch`만 허용한다. Jenkins 장애 시 수동으로
rollback 또는 emergency deployment를 실행할 수 있다.

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
| `VPS_SSH_KEY` | GitHub Actions 전용 배포 private key. |

# 관계

이 workflow는 [Traefik](/services/traefik.md), [PostgreSQL](/services/postgresql.md),
[Redis](/services/redis.md), [whoami](/services/whoami.md), [공용 인프라 포털](/services/portal.md)을 시작하고 갱신한다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
