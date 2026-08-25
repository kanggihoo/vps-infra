---
type: Deployment Service
title: GitHub Actions 검증
description: 과거 SSH 배포 경로와 현재 push/PR 설정 검증 workflow를 기록한다.
tags: [deployment, github-actions, ssh, docker-compose]
timestamp: 2026-08-25T00:00:00+09:00
---

# 상태

**자동 배포 경로로 폐기.** 현재 `.github/workflows/validate.yml`만 유지하며,
Compose·nginx·배포 대상 판정·SOPS 파일 무결성을 검증한다. 이 문서의 SSH 배포 흐름은
역사 기록이며 현재 운영 절차가 아니다.

# 개요

Jenkins migration 전 GitHub Actions가 `main` 변경을 자동 배포했다. 현재 자동 배포는
Jenkins가 담당하며, repository에는 `.github/workflows/validate.yml`만 남아 설정 검증을
수행한다. 아래 SSH 흐름은 과거 구현 기록이다.

이 서비스는 [SSH git-pull 배포 결정](/adr/0001-ssh-git-pull-deployment.md)을 구현한다.

# 과거 트리거

```yaml
on:
  push:
    branches: [main]
```

현재 workflow는 배포가 아니라 설정 검증을 수행한다. Jenkins 장애 시 수동 배포가
필요하면 관리자 SSH로 Docker 명령을 직접 실행한다.

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

이 workflow는 [nginx](/services/nginx.md), [PostgreSQL](/services/postgresql.md),
[Redis](/services/redis.md), [whoami](/services/whoami.md), [공용 인프라 포털](/services/portal.md)을 시작하고 갱신한다.
