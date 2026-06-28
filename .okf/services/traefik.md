---
type: Service
title: Traefik 리버스 프록시
description: VPS의 public HTTP/HTTPS 진입점.
tags: [traefik, reverse-proxy, tls, docker]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

Traefik은 VPS에서 public HTTP/HTTPS 포트를 노출하는 유일한 서비스다.
hostname 기준으로 Docker 서비스를 라우팅하고, HTTP를 HTTPS로 redirect하며,
Let's Encrypt HTTP-01 방식으로 TLS 인증서를 발급한다.

# Public Routes

| Hostname | 대상 | 보호 |
|----------|------|------|
| `traefik.kkh-hub.tech` | Traefik dashboard/API | Basic Auth |
| `health.kkh-hub.tech` | [whoami](/services/whoami.md) | 초기 검증 단계에서는 public |

# 책임

- `80`, `443` 포트 publish.
- HTTP -> HTTPS redirect.
- Let's Encrypt HTTP-01 인증서 발급.
- hostname 기반 라우팅.
- dashboard Basic Auth 보호.

# 제약

- 다른 서비스는 `80`, `443`을 publish하지 않는다.
- dashboard는 인증 없이 노출하지 않는다.
- ACME 인증서 상태는 VPS에만 보관하고 Git에 커밋하지 않는다.

# 관계

Traefik은 [초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 검증한다.
라우팅 방식은 [서브도메인 라우팅 결정](/decisions/subdomain-routing.md)을 따른다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
