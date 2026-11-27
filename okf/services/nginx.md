---
type: Service
title: nginx 리버스 프록시
description: VPS의 public HTTP/HTTPS 진입점.
tags: [nginx, reverse-proxy, tls, certbot, docker]
timestamp: 2026-11-27T00:00:00+09:00
---

# 개요

nginx는 VPS에서 public HTTP/HTTPS 포트를 노출하는 유일한 서비스다.
`nginx/templates/*.template`의 server block으로 hostname 기반 라우팅을 하고,
HTTP를 HTTPS로 redirect하며, `certbot` 컨테이너가 Let's Encrypt HTTP-01 방식으로
발급한 인증서를 read-only volume으로 공유받아 사용한다.

Docker label 기반 동적 라우팅은 없다. 전체 배포는 후보 템플릿을 렌더링해 `nginx -t`로
검사한 뒤 nginx를 강제 재생성한다. 템플릿만 바뀌어도 환경변수 치환 결과가 갱신된다.
완성된 설정은 컨테이너 내부 `/etc/nginx/conf.d/`에 있다.

보호 서브도메인(`erd`, `notes`, `info`, `grafana`)은 [Tinyauth SSO](../../docs/adr/0022-tinyauth-sso.md)로 인증한다.
각 server 블록이 `nginx/templates/snippets/tinyauth.conf.template`(렌더 결과 `/etc/nginx/conf.d/snippets/tinyauth.conf`)를
include한다. 모든 요청이 `auth_request /tinyauth`로 `tinyauth:3000/api/auth/nginx`에 인증을 묻고, 401이면
`auth.<도메인>/login?redirect_uri=...`로 302를 준다. `/tinyauth`는 `internal;`이고 `X-Forwarded-Host`는 `$host`로 덮어쓴다.
세션 쿠키는 상위 도메인에 걸리므로 한 번 로그인하면 4곳을 24시간 동안 다시 묻지 않는다.

# Public Routes

| Hostname | 대상 | conf 파일 |
|----------|------|-----------|
| `health.kkh-hub.tech` | [whoami](/services/whoami.md) (공개, `Cookie` 헤더 제거) | `nginx/templates/health.conf.template` |
| `auth.kkh-hub.tech` | Tinyauth 로그인 포털 (공개) | `nginx/templates/auth.conf.template` |
| `portal.kkh-hub.tech` | [공용 인프라 포털](/services/portal.md) | `nginx/templates/portal.conf.template` |
| `erd.kkh-hub.tech` | [ERD 서빙](/services/erd.md) (정적 파일, Tinyauth SSO) | `nginx/templates/erd.conf.template` |
| `notes.kkh-hub.tech` | Quartz 정적 사이트 (Tinyauth SSO) | `nginx/templates/notes.conf.template` |
| `info.kkh-hub.tech` | [vps-info](/services/vps-info.md) (Tinyauth SSO) | `nginx/templates/vps-info.conf.template` |
| `grafana.kkh-hub.tech` | [관측 스택](/services/observability.md) (Tinyauth SSO, `Remote-User` Auth Proxy) | `nginx/templates/grafana.conf.template` |

Traefik dashboard(`traefik.kkh-hub.tech`)와 SSAFY webhook 라우팅
(`ssafy.kkh-hub.tech`)은 nginx 전환과 함께 제거했다. SSAFY Workspace Webhook POC 서비스
자체도 폐기되었다. `jenkins.kkh-hub.tech`는 [ADR 0021](../../docs/adr/0021-remove-jenkins.md)로 템플릿을 지워
default server(444)로 떨어진다. `CHALLENGE_DOMAINS`와 인증서 SAN에서도 뺐다(2026-11-20 재발급). DNS A 레코드만 남아 있다.

# 인증서 발급 (certbot)

`certbot` 컨테이너는 nginx와 동일한 `certbot-www` named volume(webroot)과
`certbot-etc` named volume(`/etc/letsencrypt`)을 공유한다. nginx는
`certbot-etc`를 read-only로 mount해서 인증서를 사용한다.

- 최초 발급은 수동 1회 실행한다. `docker compose run --rm --entrypoint certbot certbot certonly
  --webroot -w /var/www/certbot -d kkh-hub.tech -d portal.kkh-hub.tech
  -d health.kkh-hub.tech`처럼 SAN 인증서 1장으로 발급해
  모든 conf가 같은 `ssl_certificate` 경로(`/etc/letsencrypt/live/kkh-hub.tech/`)를
  참조하게 한다.
- 갱신은 상주 `vps-certbot` 컨테이너가 12시간마다 확인하고, nginx가 하루 한 번 스스로
  reload해 새 인증서를 읽는다([ADR 0011](../../docs/adr/0011-certbot-container-renewal.md)).
- 새 서브도메인은 `secrets/env.prod.sops.env`의 `CHALLENGE_DOMAINS`에 넣고 push한다.
  `deploy.sh`(all 대상, `TLS_MODE=live`)가 인증서에 빠진 도메인을 찾아 전체 `-d` 목록으로
  같은 인증서(`--cert-name kkh-hub.tech`)를 `--expand`한다.
- HTTP(`:80`)의 `/.well-known/acme-challenge/`는 `nginx/templates/00-http-challenge.conf.template`가
  webroot로 정적 서빙한다. 나머지 HTTP 요청은 HTTPS로 301 redirect한다.

# 로그와 트레이스

- 이미지는 `nginx:1.31.4-alpine-otel`이다. OpenTelemetry 모듈이 요청마다 span을 Alloy(`alloy:4317`)로 보내고
  `traceparent`를 백엔드로 전파한다([ADR 0017](../../docs/adr/0017-nginx-starts-traces.md)). Alloy가 없어도 nginx는 기동하고
  export 실패만 error 로그로 남긴다.
- UptimeRobot과 Alloy blackbox probe 요청은 user agent로 걸러 trace하지 않는다.
- access log는 Grafana NGINX 연동의 `json_analytics` 포맷이다. 커뮤니티 대시보드가 이 필드 이름을 전제하므로
  원본을 유지하고 `level`(HTTP 상태 기준), `trace_id`, `span_id`만 덧붙인다.
- `vps_proxy`에서 공개 이름(`health`, `portal`, `grafana`, `auth`)을 alias로 갖는다. 컨테이너가 공개 IP로
  hairpin하지 못하므로 내부 probe가 이 alias로 nginx를 거친다.

# 책임

- `80`, `443` 포트 publish.
- HTTP -> HTTPS redirect.
- hostname 기반 라우팅 (`server_name` + 생성된 `conf.d/*.conf`).
- Grafana WebSocket 연결을 위한 `Upgrade`/`Connection` 헤더 전달(`grafana.conf.template`).
- 보호 서브도메인의 Tinyauth `auth_request`. Grafana에는 `Remote-User`를 Tinyauth 결과로 덮어쓰고 `Authorization`을 비워 넘긴다.

# 제약

- 다른 서비스는 `80`, `443`을 publish하지 않는다.
- 인증서(`certbot-etc`)와 webroot(`certbot-www`) volume은 VPS에만 상태로 존재하고
  Git에 커밋하지 않는다.
- `TLS_MODE=live` 배포는 빈 `TINYAUTH_AUTH_USERS`, 로컬 테스트 계정(`test`), 빈 `TINYAUTH_OAUTH_WHITELIST`,
  `.env`의 작은따옴표 없는 `$` 값을 거부한다(`scripts/deploy.sh`).
- `/tinyauth`와 `auth` upstream은 변수 `proxy_pass`와 `resolver 127.0.0.11`을 쓴다. tinyauth 컨테이너 없이
  `docker compose run --no-deps nginx nginx -t`가 통과해야 한다.
- `notes`는 `recursive_error_pages on;`이다. 미인증으로 `/404.html`을 부르면 404 → 401 → 로그인 302로 이어져야 한다.

# 관계

nginx는 [초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 검증한다.
라우팅 방식은 [서브도메인 라우팅 결정](../../docs/adr/0005-subdomain-routing.md)을 따른다.
