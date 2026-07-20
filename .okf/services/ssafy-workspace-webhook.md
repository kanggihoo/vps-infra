---
type: Application Service
title: SSAFY Workspace Webhook POC
description: GitLab과 Mattermost 요청을 검증하고 redacted JSON 파일로 보관하는 FastAPI POC.
tags: [ssafy-workspace, webhook, fastapi, traefik]
timestamp: 2026-07-20T00:00:00+09:00
---

# 개요

SSAFY Workspace Webhook POC는 `/opt/ssafy-workspace` repository가 배포하는 독립 FastAPI container다. GitLab CE 18.11.5와 Mattermost의 webhook·command 연결 가능성을 검증한다.

# 라우팅

`ssafy.kkh-hub.tech`의 `/healthz`, `/webhooks/gitlab`, `/webhooks/mattermost/outgoing`, `/commands/mattermost/a502`만 Traefik file provider가 전달한다. Traefik은 `vps_proxy`에서 `ssafy-webhook-receiver:8000`으로 연결한다.

# 책임 경계

- `vps-infra`: hostname, path router, Let's Encrypt TLS.
- `ssafy-workspace`: FastAPI code, image, Compose, GitHub Actions deployment.
- VPS 전용 상태: `/opt/ssafy-workspace/webhook-receiver/.env`와 `received/` JSON.

# 제약

- application port를 host에 publish하지 않는다.
- token, incoming webhook URL, 원본 payload를 Git에 기록하지 않는다.
- GitLab 18.11.5에서는 `X-Gitlab-Token`만 검증한다.

# 관계

- [Traefik](/services/traefik.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [서브도메인 라우팅](/decisions/subdomain-routing.md)
