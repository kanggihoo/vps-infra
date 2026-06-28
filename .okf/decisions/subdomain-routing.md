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
```

# 이유

서브도메인은 Traefik 라우팅이 단순하고, 앱의 base path 문제를 피한다.
나중에 SSO와 앱 onboarding을 붙일 때도 path prefix 방식보다 명확하다.

# DNS Records

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      traefik    187.77.114.68
A      health     187.77.114.68
```

# 관련 개념

- [Traefik 리버스 프록시](/services/traefik.md)
- [whoami Health Target](/services/whoami.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
