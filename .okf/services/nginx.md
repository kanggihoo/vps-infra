---
type: Service
title: nginx 리버스 프록시
description: VPS의 public HTTP/HTTPS 진입점.
tags: [nginx, reverse-proxy, tls, certbot, docker]
timestamp: 2026-08-10T00:00:00+09:00
---

# 개요

nginx는 VPS에서 public HTTP/HTTPS 포트를 노출하는 유일한 서비스다.
`nginx/conf.d/*.conf`의 정적 server block으로 hostname 기반 라우팅을 하고,
HTTP를 HTTPS로 redirect하며, `certbot` 컨테이너가 Let's Encrypt HTTP-01 방식으로
발급한 인증서를 read-only volume으로 공유받아 사용한다.

Traefik과 달리 Docker label 기반 동적 라우팅은 없다. 서비스를 추가하거나 라우팅을
바꾸려면 `nginx/conf.d/`에 conf 파일을 추가/수정하고 `docker compose restart nginx`
(또는 `nginx -s reload`)로 반영해야 한다.

# Public Routes

| Hostname | 대상 | conf 파일 |
|----------|------|-----------|
| `health.kkh-hub.tech` | [whoami](/services/whoami.md) | `nginx/conf.d/health.conf` |
| `portal.kkh-hub.tech` | [공용 인프라 포털](/services/portal.md) | `nginx/conf.d/portal.conf` |
| `jenkins.kkh-hub.tech` | [Jenkins](/services/jenkins-deploy.md) | `nginx/conf.d/jenkins.conf` |

Traefik dashboard(`traefik.kkh-hub.tech`)와 SSAFY webhook 라우팅
(`ssafy.kkh-hub.tech`)은 nginx 전환과 함께 제거했다. SSAFY Workspace Webhook POC는
현재 `vps-infra`를 통해 외부로 노출되지 않는다.

# 인증서 발급 (certbot)

`certbot` 컨테이너는 nginx와 동일한 `certbot-www` named volume(webroot)과
`certbot-etc` named volume(`/etc/letsencrypt`)을 공유한다. nginx는
`certbot-etc`를 read-only로 mount해서 인증서를 사용한다.

- 최초 발급은 수동 1회 실행한다. `docker compose run --rm certbot certonly
  --webroot -w /var/www/certbot -d kkh-hub.tech -d portal.kkh-hub.tech
  -d health.kkh-hub.tech -d jenkins.kkh-hub.tech`처럼 SAN 인증서 1장으로 발급해
  모든 conf가 같은 `ssl_certificate` 경로(`/etc/letsencrypt/live/kkh-hub.tech/`)를
  참조하게 한다.
- 갱신은 `certbot` 컨테이너의 entrypoint가 12시간 주기로 `certbot renew`를
  반복 실행하며 자동 처리한다. 운영 배포 스크립트(`scripts/deploy.sh`)는 발급
  로직을 포함하지 않는다.
- HTTP(`:80`)의 `/.well-known/acme-challenge/`는 `nginx/conf.d/00-http-challenge.conf`가
  webroot로 정적 서빙한다. 나머지 HTTP 요청은 HTTPS로 301 redirect한다.

# 책임

- `80`, `443` 포트 publish.
- HTTP -> HTTPS redirect.
- hostname 기반 라우팅 (`server_name` + `conf.d/*.conf`).
- Jenkins WebSocket/장시간 연결을 위한 `proxy_http_version 1.1`, `Upgrade`/`Connection`
  헤더 전달.

# 제약

- 다른 서비스는 `80`, `443`을 publish하지 않는다.
- 인증서(`certbot-etc`)와 webroot(`certbot-www`) volume은 VPS에만 상태로 존재하고
  Git에 커밋하지 않는다.
- Traefik 시절 존재하던 dashboard/Basic Auth 보호 대상은 없다. 상태 확인은
  `health.kkh-hub.tech` 응답과 `docker compose ps`로 대체한다.

# 관계

nginx는 [초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 검증한다.
라우팅 방식은 [서브도메인 라우팅 결정](/decisions/subdomain-routing.md)을 따른다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
