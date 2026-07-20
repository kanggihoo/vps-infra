---
type: Architecture
title: 시스템 아키텍처 개요
description: Hostinger VPS 1대에서 Jenkins, Traefik, Docker Compose, PostgreSQL, Redis가 연결되는 전체 구조.
tags: [architecture, vps, docker-compose, traefik, deployment]
timestamp: 2026-06-29T00:00:00+09:00
---

# 개요

이 프로젝트는 Hostinger VPS 1대에서 공통 인프라를 Docker Compose로 운영한다.
외부 traffic은 [Traefik 리버스 프록시](/services/traefik.md)만 받고, PostgreSQL과
Redis는 Docker internal network 안에서만 접근한다.

# 배포 구조

```txt
GitHub main
  -> GitHub webhook
    -> Jenkins container
      -> /opt/vps-infra checkout
        -> docker compose up -d
```

[Jenkins 배포](/services/jenkins-deploy.md)는 `main` 변경을 트리거로 Pipeline을
실행한다. Jenkins는 VPS의 `/opt/vps-infra` checkout을 갱신하고 Docker Compose를
적용한다. GitHub Actions workflow는 자동 배포에 사용하지 않는다.

# 런타임 구조

```txt
Internet
  -> DNS: kkh-hub.tech
    -> VPS 187.77.114.68
      -> Traefik :80/:443
        -> Docker internal network
          -> Jenkins
          -> whoami
          -> portal
          -> ssafy-webhook-receiver
          -> PostgreSQL
          -> Redis
```

# Docker 네트워크

| Compose network | Docker network | 용도 |
|-----------------|----------------|------|
| `proxy` | `vps_proxy` | Traefik과 public HTTP backend가 연결되는 라우팅 경계. |
| `data` | `vps_data` | PostgreSQL과 Redis가 외부 port publish 없이 연결되는 내부 데이터 경계. |

# 라우팅 구조

```txt
traefik.kkh-hub.tech
  -> Traefik dashboard
  -> Basic Auth 보호

health.kkh-hub.tech
  -> traefik/whoami
  -> DNS/TLS/routing 검증용

ssafy.kkh-hub.tech
  -> exact webhook/command paths
  -> ssafy-webhook-receiver:8000
```

라우팅은 [서브도메인 라우팅](/decisions/subdomain-routing.md) 결정을 따른다.
서브도메인을 서비스 경계로 사용하고, 한 제품에서 여러 backend가 필요한 경우에만
명시된 exact path로 내부 서비스를 구분한다.

# 서비스 경계

| 서비스 | 경계 | 외부 노출 |
|--------|------|-----------|
| [Traefik](/services/traefik.md) | public HTTP/HTTPS entrypoint | `80`, `443` |
| [Jenkins](/services/jenkins-deploy.md) | GitHub webhook와 배포 Pipeline | Traefik 뒤 HTTPS만 |
| [whoami](/services/whoami.md) | Traefik 뒤 검증용 HTTP backend | 직접 노출 없음 |
| [SSAFY Workspace Webhook POC](/services/ssafy-workspace-webhook.md) | GitLab·Mattermost 연결 검증 | Traefik exact path만 공개 |
| [PostgreSQL](/services/postgresql.md) | 공통 DB container | `5432` 미노출 |
| [Redis](/services/redis.md) | 공통 cache/session container | `6379` 미노출 |

# 데이터 서비스 격리 방향

초기 단계에서는 PostgreSQL과 Redis를 실행 상태로 검증하는 것이 목표다. 실제 앱이
생기면 [공통 데이터 서비스](/decisions/shared-data-services.md) 결정에 따라 격리한다.

PostgreSQL:

```txt
1 PostgreSQL container
-> app1_db + app1_user
-> app2_db + app2_user
```

Redis:

```txt
1 Redis container
-> app1_user -> ~app1:* access
-> app2_user -> ~app2:* access
```

# 운영 파일 경계

Git에 포함한다.

```txt
compose.yml
traefik config
deploy workflow
scripts
.env.example
docs
.okf
```

VPS에만 둔다.

```txt
.env
traefik/acme.json
PostgreSQL volume data
Redis volume data
backups
```

# 재부팅 복구

재부팅 복구는 [Docker 재시작 복구](/decisions/docker-restart-recovery.md) 결정을 따른다.

```txt
sudo systemctl enable docker
+
restart: unless-stopped
```

Docker daemon이 boot 시 자동 시작되고, 이미 생성된 container는 restart policy에 따라
다시 올라온다.

# 핵심 원칙

- VPS 외부 공개는 Traefik만 담당한다.
- 내부 서비스는 Docker network 안에서만 접근한다.
- 배포는 VPS 내부 Jenkins가 GitHub webhook을 받아 Compose를 갱신한다.
- secret과 runtime state는 Git에 커밋하지 않는다.

# 관련 개념

- [Hostinger VPS](/environments/hostinger-vps.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [Traefik 리버스 프록시](/services/traefik.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
