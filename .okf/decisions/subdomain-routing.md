---
type: Decision
title: 서브도메인 라우팅
description: 초기 라우팅은 path prefix 대신 서브도메인을 사용한다.
tags: [dns, nginx, routing, tls]
timestamp: 2026-08-10T00:00:00+09:00
---

# 결정

public service 라우팅은 서브도메인 기반으로 한다.

현재 route:

```txt
health.kkh-hub.tech  -> whoami
portal.kkh-hub.tech  -> 공용 인프라 포털
jenkins.kkh-hub.tech -> Jenkins
```

Traefik dashboard(`traefik.kkh-hub.tech`)와 SSAFY Workspace webhook exact path
라우팅(`ssafy.kkh-hub.tech`)은 nginx 전환과 함께 제거했다.

# 이유

서브도메인은 라우팅이 단순하고, 앱의 base path 문제를 피한다.
나중에 SSO와 앱 onboarding을 붙일 때도 path prefix 방식보다 명확하다.
한 제품 서브도메인 아래 여러 backend가 필요하면 catch-all path prefix 대신 필요한
exact path만 각 backend에 할당한다.

nginx는 Docker label 기반 동적 라우팅이 없으므로, 서브도메인 하나당
`nginx/conf.d/*.conf` 파일 하나를 대응시켜 Traefik의 `dynamic/*.yml` 파일 단위
패턴을 유지한다.

# DNS Records

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      health     187.77.114.68
A      portal     187.77.114.68
A      jenkins    187.77.114.68
```

# 관련 개념

- [nginx 리버스 프록시](/services/nginx.md)
- [whoami Health Target](/services/whoami.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
