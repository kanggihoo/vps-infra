---
type: Decision
title: 서브도메인 라우팅
description: 초기 Traefik 라우팅은 path prefix 대신 서브도메인을 사용한다.
tags: [dns, traefik, routing, tls]
timestamp: 2026-06-28T00:00:00+09:00
---

# 결정

public service 라우팅은 서브도메인 기반으로 한다.

초기 route:

```txt
traefik.kkh-hub.tech -> Traefik dashboard
health.kkh-hub.tech  -> whoami
portal.kkh-hub.tech  -> 공용 인프라 포털
ssafy.kkh-hub.tech   -> SSAFY Workspace
```

# 이유

서브도메인은 Traefik 라우팅이 단순하고, 앱의 base path 문제를 피한다.
나중에 SSO와 앱 onboarding을 붙일 때도 path prefix 방식보다 명확하다.
한 제품 서브도메인 아래 여러 backend가 필요하면 catch-all path prefix 대신 필요한
exact path만 각 backend에 할당한다. SSAFY Workspace POC는 webhook/command 네 경로만
FastAPI에 전달한다.

# DNS Records

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      traefik    187.77.114.68
A      health     187.77.114.68
A      portal     187.77.114.68
A      ssafy      187.77.114.68
```

# 관련 개념

- [Traefik 리버스 프록시](/services/traefik.md)
- [whoami Health Target](/services/whoami.md)
- [SSAFY Workspace Webhook POC](/services/ssafy-workspace-webhook.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
