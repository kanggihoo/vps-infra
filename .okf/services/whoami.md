---
type: Service
title: whoami Health Target
description: DNS, TLS, Traefik 라우팅, Docker 네트워크를 검증하는 가벼운 HTTP 컨테이너.
tags: [healthcheck, traefik, docker]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

`traefik/whoami`는 [Traefik](/services/traefik.md) 뒤에 두는 첫 HTTP 대상이다.
요청을 받으면 hostname, IP, forwarded header 같은 요청 메타데이터를 반환한다.

# Route

```txt
https://health.kkh-hub.tech -> whoami
```

# 검증 가치

이 서비스로 다음을 확인한다.

- DNS가 VPS를 가리킨다.
- TLS 인증서가 발급되고 serving된다.
- Traefik hostname 라우팅이 동작한다.
- Docker internal network가 동작한다.
- backend container가 reverse proxy 뒤에서 응답한다.

# 생명주기

실제 앱이 올라온 뒤에는 제거하거나 단순 health endpoint로 유지할 수 있다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
