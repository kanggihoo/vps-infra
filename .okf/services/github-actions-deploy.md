---
type: Deployment Service
title: GitHub Actions 배포
description: main 변경 시 GitHub Actions가 SSH로 VPS에 접속해 배포한다.
tags: [deployment, github-actions, ssh, docker-compose]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

GitHub Actions는 `main` 브랜치가 변경되면 인프라 repository를 배포한다.
workflow는 Hostinger VPS에 `kkh` 사용자로 SSH 접속하고, `/opt/vps-infra`
repository를 갱신한 뒤 Docker Compose를 적용한다.

이 서비스는 [SSH git-pull 배포 결정](/decisions/ssh-git-pull-deployment.md)을 구현한다.

# 트리거

```yaml
on:
  push:
    branches: [main]
```

1차 단계에는 `workflow_dispatch`를 넣지 않는다. 코드 변경 없이 재배포해야 하는
운영 요구가 생기면 나중에 추가한다.

# 흐름

```txt
main 변경
-> GitHub Actions 실행
-> VPS에 kkh 사용자로 SSH 접속
-> cd /opt/vps-infra
-> git pull origin main
-> docker compose config
-> docker compose pull
-> docker compose up -d
-> docker compose ps
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
[Redis](/services/redis.md), [whoami](/services/whoami.md)를 시작하고 갱신한다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
