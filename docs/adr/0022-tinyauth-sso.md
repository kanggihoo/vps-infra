---
type: Decision
title: 보호 서브도메인을 Basic Auth 대신 Tinyauth SSO로 지킨다
description: erd·notes·info·grafana를 nginx auth_request + Tinyauth 하나로 묶어 24시간 쿠키 세션 SSO로 보호하고, 로컬 계정과 Google OAuth(화이트리스트)를 함께 쓴다. Basic Auth 파일과 스크립트를 지운다.
tags: [auth, tinyauth, sso, nginx, grafana, security]
timestamp: 2026-11-27T00:00:00+09:00
---

# 상태

채택. [ADR 0013](0013-liam-erd-static-hosting.md)의 "공용 Basic Auth를 건다"와 [ADR 0010](0010-sops-secrets.md)의
Basic Auth 암호화 대상을 대체한다. 스펙과 결정 로그는 레포의 `docs/specs/tinyauth-sso/`에 있다.

# 결정

- Tinyauth(`ghcr.io/tinyauthapp/tinyauth:v5.2.0`)를 루트 `compose.yml`의 `tinyauth` 서비스로 띄운다. 로그인 포털은 `auth.<BASE_DOMAIN>`이다.
- 보호 대상은 `erd`, `notes`, `info`, `grafana` 4곳이다. `portal`, `health`, `auth`는 공개다.
- nginx 보호 server 블록은 공용 snippet(`nginx/templates/snippets/tinyauth.conf.template`)을 include한다.
  모든 요청이 `auth_request /tinyauth` → `tinyauth:3000/api/auth/nginx`를 거친다. 401이면 로그인 URL로 302를 준다.
  `/tinyauth`는 `internal;`, `X-Forwarded-Host`는 `$host`로 덮어쓴다.
- 인증 수단은 로컬 계정(`TINYAUTH_AUTH_USERS`, `user:bcrypt`)과 Google OAuth다. Google은 `TINYAUTH_OAUTH_WHITELIST`에 있는 이메일만 통과한다.
  로컬 계정 TOTP는 쓰지 않는다.
- 세션은 24시간(`TINYAUTH_AUTH_SESSIONEXPIRY=86400`)이고 쿠키는 상위 도메인에 걸린다. 세션 DB(SQLite)는 `vps_tinyauth_data` volume에 둔다.
- Grafana는 Auth Proxy로 바꾼다(`GF_AUTH_PROXY_ENABLED`, `Remote-User`, 자동 가입 Admin). 로그인 폼과 Basic Auth API는 끈다.
  nginx는 `/`와 `/api/live/` 모두에서 `Remote-User`를 Tinyauth 결과로 덮어쓰고 `Authorization`을 비운다.
- 모든 보호 대상이 같은 허용 목록을 쓴다. Tinyauth에 `/var/run/docker.sock`을 마운트하지 않는다(label 기반 서비스별 ACL 없음).
- 설정은 `secrets/env.{local,prod}.sops.env` 하나로 모은다. `secrets/basic-auth.htpasswd.sops.txt`,
  `nginx/test-fixtures/basic-auth.htpasswd`, `scripts/set-basic-auth.sh`를 지운다.
- 로컬 `BASE_DOMAIN`은 `vps.localhost`다. Tinyauth v5는 `localhost`를 TLD로 보고 쿠키를 `auth.localhost`에만 걸어
  `erd.localhost` 등에서 SSO가 되지 않는다(2026-11-27 실측).
- `scripts/deploy.sh`는 `TLS_MODE=live`에서 빈 `TINYAUTH_AUTH_USERS`, 로컬 테스트 계정(`test`), 빈 `TINYAUTH_OAUTH_WHITELIST`를 거부한다.
  환경과 상관없이 `.env`의 작은따옴표 없는 `$` 값과, Google client가 있는데 빈 화이트리스트도 거부한다.
- 관측: Alloy는 `auth.<도메인>`을 공개 probe하고 Grafana는 `http://grafana:3000/api/health`를 내부에서 본다.
  `healthcheck.sh`는 `auth` 공개 헬스, Grafana 내부 헬스, 보호 4곳의 로그인 302를 확인한다.

# 이유

- Basic Auth는 브라우저 로그아웃과 세션 만료를 제어할 수 없고, 서브도메인마다 자격증명을 다시 묻는다.
- Basic Auth는 `Authorization` 헤더를 점유해 Grafana 자체 로그인과 겹칠 수 없었다. 그래서 Grafana만 따로 계정을 두었다.
- SOPS 대상이 `.env`와 `htpasswd` 두 종류라 복호화·관리 스크립트가 이원화되어 있었다.
- Tinyauth는 상주 메모리가 작고, nginx `auth_request`와 바로 붙는다. Authelia·Authentik보다 설정이 짧다.
- Grafana `/api/health`만 인증 예외로 열면 보호 서브도메인에 무인증 경로가 남는다. 그래서 내부 주소로 본다.

# 결과

수용한 트레이드오프 4건:

1. **`vps_proxy` 내부 신뢰.** Grafana는 `Remote-User` 헤더를 그대로 믿는다. nginx를 거치지 않고 `vps_proxy`에서
   `grafana:3000`에 직접 붙는 컨테이너는 아무 사용자로 들어갈 수 있다. 같은 네트워크의 컨테이너는 신뢰한다는 전제다.
2. **Grafana 계정 이중 생성.** 같은 사람이라도 로컬 계정과 Google 계정으로 들어오면 Grafana 사용자가 두 개(둘 다 Admin) 생긴다.
3. **`portal`로의 세션 쿠키 전송.** 쿠키가 상위 도메인에 걸리므로 공개 서브도메인 `portal`에도 전송된다. `portal`이 쿠키를
   기록하거나 반사하지 않는다는 전제다. `health`(whoami)는 받은 헤더를 반사하므로 nginx가 `Cookie`를 지운다.
4. **세션 회수 지연.** 화이트리스트·계정을 바꿔도 이미 발급된 세션은 최대 24시간 유효하다.
   Tinyauth v5에는 서명 시크릿이 없어(쿠키는 무작위 세션 ID, DB로 검증) 시크릿 교체로 무효화할 수 없다.
   긴급 회수는 세션 DB를 지운다.

   ```bash
   docker compose stop tinyauth
   docker volume rm vps_tinyauth_data
   docker compose up -d tinyauth   # 모든 사용자가 다시 로그인한다
   ```

그 밖의 결과:

- 운영 배포 전에 `secrets/env.prod.sops.env`에 `TINYAUTH_AUTH_USERS`, `TINYAUTH_OAUTH_WHITELIST`, Google client를 채워야 한다.
  비어 있으면 `deploy.sh`가 스택을 바꾸기 전에 멈춘다. `auth.kkh-hub.tech` DNS A 레코드는 운영자가 등록하고,
  인증서는 `CHALLENGE_DOMAINS`의 `auth.kkh-hub.tech`로 `deploy.sh`가 `--expand`한다.
- 로컬 주소가 `*.vps.localhost`로 바뀐다(`http://portal.vps.localhost` 등).
- 검증: `scripts/test-nginx-templates.sh`(문법), `scripts/test-deploy-guards.sh`(배포 가드),
  `scripts/test-routing.sh`(로컬 쿠키 SSO E2E), `scripts/healthcheck.sh`.

# 거절한 대안

- **Basic Auth 유지**: 위 이유로 거절.
- **Grafana 자체 로그인 유지**: 계정과 비밀번호를 따로 관리해야 한다.
- **Docker label 기반 서비스별 ACL**: `docker.sock` 마운트가 필요하고 지금은 사용자가 한 명이다.
  다른 사용자에게 일부 서비스만 열어야 할 때 다시 검토한다.
- **화이트리스트 없는 Google OAuth**: 아무 Google 계정이나 통과한다.
- **7일 세션**: 노출 기간이 길다. **비영속 세션**: 재배포마다 로그아웃된다.

# 관련 개념

- [nginx 리버스 프록시](../../okf/services/nginx.md)
- [ERD 서빙](../../okf/services/erd.md)
- [관측 스택](../../okf/services/observability.md)
- [SOPS 기반 secret 관리](0010-sops-secrets.md)
- [nginx 설정의 환경 템플릿화](0008-nginx-env-templates.md)
