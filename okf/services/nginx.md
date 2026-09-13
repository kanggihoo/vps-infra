---
type: Service
title: nginx 리버스 프록시
description: VPS의 public HTTP/HTTPS 진입점.
tags: [nginx, reverse-proxy, tls, certbot, docker]
timestamp: 2026-09-13T00:00:00+09:00
---

# 개요

nginx는 VPS에서 public HTTP/HTTPS 포트를 노출하는 유일한 서비스다.
`nginx/templates/*.template`의 server block으로 hostname 기반 라우팅을 하고,
HTTP를 HTTPS로 redirect하며, `certbot` 컨테이너가 Let's Encrypt HTTP-01 방식으로
발급한 인증서를 read-only volume으로 공유받아 사용한다.

Docker label 기반 동적 라우팅은 없다. 전체 배포는 후보 템플릿을 렌더링해 `nginx -t`로
검사한 뒤 nginx를 강제 재생성한다. 템플릿만 바뀌어도 환경변수 치환 결과가 갱신된다.
완성된 설정은 컨테이너 내부 `/etc/nginx/conf.d/`에 있다.

# Public Routes

| Hostname | 대상 | conf 파일 |
|----------|------|-----------|
| `health.kkh-hub.tech` | [whoami](/services/whoami.md) | `nginx/templates/health.conf.template` |
| `portal.kkh-hub.tech` | [공용 인프라 포털](/services/portal.md) | `nginx/templates/portal.conf.template` |
| `jenkins.kkh-hub.tech` | [Jenkins](/services/jenkins-deploy.md) | `nginx/templates/jenkins.conf.template` |

Traefik dashboard(`traefik.kkh-hub.tech`)와 SSAFY webhook 라우팅
(`ssafy.kkh-hub.tech`)은 nginx 전환과 함께 제거했다. SSAFY Workspace Webhook POC는
현재 `vps-infra`를 통해 외부로 노출되지 않는다.

# 인증서 발급 (certbot)

`certbot` 컨테이너는 nginx와 동일한 `certbot-www` named volume(webroot)과
`certbot-etc` named volume(`/etc/letsencrypt`)을 공유한다. nginx는
`certbot-etc`를 read-only로 mount해서 인증서를 사용한다.

- 최초 발급은 수동 1회 실행한다. `docker compose run --rm --entrypoint certbot certbot certonly
  --webroot -w /var/www/certbot -d kkh-hub.tech -d portal.kkh-hub.tech
  -d health.kkh-hub.tech -d jenkins.kkh-hub.tech`처럼 SAN 인증서 1장으로 발급해
  모든 conf가 같은 `ssl_certificate` 경로(`/etc/letsencrypt/live/kkh-hub.tech/`)를
  참조하게 한다.
- 갱신은 호스트의 `vps-infra-certbot-renew.timer`가 12시간마다 실행한다.
  `scripts/renew-certificates.sh`가 certbot 갱신 성공 뒤 `nginx -t`와 reload를 수행한다.
  certbot은 일반 Compose 기동 시 상주하지 않는다.
- HTTP(`:80`)의 `/.well-known/acme-challenge/`는 `nginx/templates/00-http-challenge.conf.template`가
  webroot로 정적 서빙한다. 나머지 HTTP 요청은 HTTPS로 301 redirect한다.

# 책임

- `80`, `443` 포트 publish.
- HTTP -> HTTPS redirect.
- hostname 기반 라우팅 (`server_name` + 생성된 `conf.d/*.conf`).
- Jenkins WebSocket/장시간 연결을 위한 `proxy_http_version 1.1`, `Upgrade`/`Connection`
  헤더 전달.

# 제약

- 다른 서비스는 `80`, `443`을 publish하지 않는다.
- 인증서(`certbot-etc`)와 webroot(`certbot-www`) volume은 VPS에만 상태로 존재하고
  Git에 커밋하지 않는다.
- `TLS_MODE=live` 배포는 공개 notes fixture를 거부한다. `NOTES_HTPASSWD`에 SOPS로
  복호화한 실제 파일을 지정해야 한다.
- 이전 Traefik 시절 존재하던 dashboard/Basic Auth 보호 대상은 없다. 상태 확인은
  `health.kkh-hub.tech` 응답과 `docker compose ps`로 대체한다.

# 관계

nginx는 [초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 검증한다.
라우팅 방식은 [서브도메인 라우팅 결정](/adr/0005-subdomain-routing.md)을 따른다.
