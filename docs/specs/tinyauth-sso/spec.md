# Tinyauth SSO

Status: approved
Decisions: [decisions.md](decisions.md) · Glossary and ADRs: [0008](../../../okf/adr/0008-nginx-env-templates.md), [0010](../../../okf/adr/0010-sops-secrets.md), [0016](../../../okf/adr/0016-self-hosted-observability.md)

## Problem

현재 VPS 인프라는 `erd`, `notes`, `info` 3개 서브도메인을 nginx `auth_basic`과 공용 `htpasswd`(SOPS+age 암호화 파일 `secrets/basic-auth.htpasswd.sops.txt`)로 보호하고 있다. 이 방식은 브라우저 로그아웃과 세션 만료 제어가 불가능하고, 서브도메인마다 자격증명을 다시 입력해야 하며, `Authorization` 헤더를 점유해 자체 로그인이 있는 `grafana`와 통합할 수 없다. 또한 SOPS 암호화 대상이 `.env`와 `htpasswd` 두 종류로 이원화되어 있다.

이를 경량 forward-auth 게이트웨이인 Tinyauth(`auth.${BASE_DOMAIN}`)로 교체해 로컬 계정(ID/PW)과 Google OAuth(이메일 화이트리스트)를 동시에 지원하고, `erd`·`notes`·`info`·`grafana` 4개 서브도메인을 24시간 단일 쿠키 세션(SSO)으로 통합 보호하며, 인증 설정을 SOPS `.env` 하나로 단일화한다.

## Usage

### 1. 미인증 브라우저 요청 → 로그인 → SSO 통과
```txt
client = curl --resolve erd.vps.localhost:80:127.0.0.1 --resolve auth.vps.localhost:80:127.0.0.1
GET http://erd.vps.localhost/probe/
  -> 302 Location: http://auth.vps.localhost/login?redirect_uri=http://erd.vps.localhost/probe/

POST http://auth.vps.localhost/api/user/login  (로컬 계정 JSON 또는 Google OAuth 콜백)
  -> 200 Set-Cookie: tinyauth-session-<hash>=...; Domain=vps.localhost; Max-Age=86400

GET http://erd.vps.localhost/probe/  (동일 쿠키 jar)
  -> 200 (정적 ERD 응답)
GET http://grafana.vps.localhost/    (동일 쿠키 jar)
  -> 200 (nginx가 Remote-User 전달 -> Grafana Admin 자동 로그인)
```

### 2. 공개 서브도메인과 쿠키 격리
```txt
GET http://portal.vps.localhost/
  -> 200 (인증 없이 통과)

GET http://health.vps.localhost/  (로그인 쿠키 보유 상태)
  -> 200 (응답 본문에 Cookie 헤더가 반사되지 않음)
```

### 3. 운영 배포 가드 (`TLS_MODE=live`)
```txt
.env에 빈 TINYAUTH_AUTH_USERS·로컬 테스트 계정·빈 TINYAUTH_OAUTH_WHITELIST·따옴표 없는 $ 포함 시:
./scripts/deploy.sh all
  -> exit non-zero (스택 기동 전 즉시 중단)
```

## Acceptance criteria

- [x] AC-1: 미인증 요청이 `erd.${BASE_DOMAIN}`, `notes.${BASE_DOMAIN}`, `info.${BASE_DOMAIN}`, `grafana.${BASE_DOMAIN}`의 어떤 경로(루트, 정적 자산, `/api/live/` WebSocket, `notes`의 `/404.html` 포함)로 들어와도 `200`을 반환하지 않고 `auth.${BASE_DOMAIN}` 로그인 URL로 `302` 리다이렉트한다 (D-1, D-3, D-10).
- [x] AC-2: `portal.${BASE_DOMAIN}`과 `health.${BASE_DOMAIN}`, `auth.${BASE_DOMAIN}`은 미인증 상태에서 접근 가능하며, `health.${BASE_DOMAIN}`은 `nginx`가 `Cookie` 헤더를 제거해 `whoami` 응답 본문에 세션 쿠키가 반사되지 않는다 (D-1, D-3, D-8).
- [x] AC-3: 로컬 계정(ID/PW) 로그인 또는 허용 이메일 화이트리스트(`TINYAUTH_OAUTH_WHITELIST`)에 포함된 Google OAuth 로그인에 성공하면 `24시간(86400초)` 만료 쿠키 세션이 발급되고, 동일 상위 도메인 아래 보호 대상 4곳에 재로그인 없이 접근할 수 있다 (D-2, D-8).
- [x] AC-4: Google OAuth 화이트리스트에 없는 이메일은 로그인에 실패(거부)하며, `TINYAUTH_OAUTH_WHITELIST`가 비어 있는 상태에서 Google OAuth로 임의 계정이 통과하지 않는다 (D-2, D-10).
- [x] AC-5: 보호 서브도메인의 `/tinyauth` subrequest `location`은 `internal;`로 외부 직접 호출이 차단되며, `X-Forwarded-Host`는 nginx `$host`로 덮어쓰여 헤더 스푸핑으로 인증을 우회할 수 없다 (D-10).
- [x] AC-6: Grafana(`grafana.${BASE_DOMAIN}`)는 `/`와 `/api/live/` 모두 `Remote-User` 헤더 기반 Admin 자동 로그인만 허용하고 자체 로그인 폼 및 Basic Auth API는 비활성화되며, nginx가 `Remote-User`를 Tinyauth 결과로 덮어쓰고 `Authorization` 헤더를 비워 클라이언트 위조 헤더가 통과하지 않는다 (D-6, D-10).
- [x] AC-7: Tinyauth 세션 DB(SQLite)는 named volume(`vps_tinyauth_data`)에 저장되어 컨테이너 재배포 후에도 유효한 24시간 세션이 유지된다 (D-8).
- [x] AC-8: `secrets/basic-auth.htpasswd.sops.txt`, `nginx/test-fixtures/basic-auth.htpasswd`, `scripts/set-basic-auth.sh` 및 관련 참조가 제거되고, `scripts/secrets.sh decrypt`와 `scripts/check-sops.sh`가 `secrets/env.{local,prod}.sops.env` 단일 체계로 통과한다 (D-5).
- [x] AC-9: `TLS_MODE=none` 로컬 clean clone 환경(`BASE_DOMAIN=vps.localhost`)에서는 Google OAuth 설정 없이 테스트 계정만으로 스택 기동, `--no-deps` `nginx -t` 문법 검사, 그리고 `curl --resolve` 기반 `scripts/test-routing.sh` 쿠키 세션 검증이 모두 통과한다 (D-1, D-9).
- [x] AC-10: `TLS_MODE=live` 배포 시 `scripts/deploy.sh`는 빈 `TINYAUTH_AUTH_USERS`·로컬 테스트 계정·빈 `TINYAUTH_OAUTH_WHITELIST`·`.env` 내 따옴표 없는 `$` 값을 감지하면 즉시 실패로 중단하고, 정상 설정에서는 `CHALLENGE_DOMAINS`에 포함된 `auth.${BASE_DOMAIN}` 인증서 확장을 수행한다 (D-3, D-5, D-9, D-10).
- [x] AC-11: `observability/alloy/config.alloy`는 `grafana`를 내부 주소(`http://grafana:3000/api/health`)로 probe하고 `auth.${BASE_DOMAIN}` 공개 probe를 포함하며, `scripts/healthcheck.sh`는 `auth.${BASE_DOMAIN}` 공개 헬스, `http://grafana:3000/api/health` 내부 헬스, 보호 라우트의 `302` 리다이렉트를 모두 검증한다 (D-7).
- [x] AC-12: 보호 대상 4곳은 동일한 전역 허용 사용자 목록을 공유하며 Tinyauth 컨테이너에 `/var/run/docker.sock`을 마운트하지 않는다 (D-4).
- [x] AC-13: Basic Auth → Tinyauth 전환을 기록한 새 ADR(`okf/adr/0022-...`)과 갱신된 OKF 문서(`nginx.md`, `erd.md`, `0010-sops-secrets.md`)가 OKF strict validation을 통과하고, 새 ADR의 Consequences 절에 수용된 트레이드오프 4건이 기록된다 (D-11).

## Interfaces

### 1. 서브도메인 라우팅 및 보호 경계
| Hostname | 대상 | 인증 정책 | 비고 |
|---|---|---|---|
| `auth.${BASE_DOMAIN}` | `tinyauth:3000` | 공개 | 로그인 포털 및 OAuth 콜백 |
| `erd.${BASE_DOMAIN}` | `/var/www/erd` (정적) | Tinyauth `auth_request` | 전역 허용 목록 |
| `notes.${BASE_DOMAIN}` | `/var/www/notes` (정적) | Tinyauth `auth_request` | `/404.html`은 `internal;` 유지 |
| `info.${BASE_DOMAIN}` | `vps-info-app:8000` | Tinyauth `auth_request` | 전역 허용 목록 |
| `grafana.${BASE_DOMAIN}` | `grafana:3000` | Tinyauth `auth_request` + `Remote-User` | `/`, `/api/live/` 모두 적용, `Authorization ""` |
| `portal.${BASE_DOMAIN}` | `portal:8080` | 공개 | 상위 도메인 쿠키 전송 수용 |
| `health.${BASE_DOMAIN}` | `whoami:80` | 공개 | `proxy_set_header Cookie "";` 적용 |

### 2. nginx `auth_request` subrequest 계약
```nginx
location = /tinyauth {
    internal;
    resolver 127.0.0.11 valid=10s ipv6=off;
    set $tinyauth_upstream "tinyauth:3000";
    proxy_pass http://$tinyauth_upstream/api/auth/nginx;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Uri $request_uri;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```
- 보호 `location`에서 미인증 `401` 수신 시 `http(s)://auth.${BASE_DOMAIN}/login?redirect_uri=$scheme://$http_host$request_uri`로 `302` 리다이렉트한다.
- Grafana `location /` 및 `location /api/live/`에서는 `auth_request_set $tinyauth_user $upstream_http_remote_user;` 결과를 `proxy_set_header Remote-User $tinyauth_user;`로 강제 덮어쓰고 `proxy_set_header Authorization "";`로 초기화한다.

### 3. Tinyauth · Grafana 환경변수 및 볼륨 계약 (`.env` / Compose)
```dotenv
# Tinyauth (SOPS env.{local,prod}.sops.env에 통합, bcrypt $ 포함 값은 작은따옴표 필수)
TINYAUTH_APPURL=https://auth.kkh-hub.tech          # 로컬: http://auth.vps.localhost
TINYAUTH_AUTH_USERS='user:$2a$10$...'               # 쉼표 구분 user:bcrypt_hash
TINYAUTH_AUTH_SESSIONEXPIRY=86400                   # 24시간(초)
TINYAUTH_OAUTH_WHITELIST=user@gmail.com             # TLS_MODE=live 시 필수
TINYAUTH_OAUTH_PROVIDERS_GOOGLE_CLIENTID=...
TINYAUTH_OAUTH_PROVIDERS_GOOGLE_CLIENTSECRET=...
CHALLENGE_DOMAINS="... auth.kkh-hub.tech"
```
- Tinyauth 세션 볼륨: `vps_tinyauth_data` (`/data` 또는 Tinyauth SQLite 경로 마운트).
- Tinyauth v5는 서명 시크릿 설정이 없다. 세션은 쿠키의 무작위 ID를 SQLite에서 조회해 검증한다 (D-8).
- Grafana 환경변수(`observability/compose.yml`): `GF_AUTH_PROXY_ENABLED=true`, `GF_AUTH_PROXY_HEADER_NAME=Remote-User`, `GF_AUTH_PROXY_AUTO_SIGN_UP=true`, `GF_USERS_AUTO_ASSIGN_ORG_ROLE=Admin`, `GF_AUTH_DISABLE_LOGIN_FORM=true`, `GF_AUTH_BASIC_ENABLED=false`.

## Constraints

- **전역 ACL 기본 동작 (D-4, provisional):** 현재는 보호 대상 4곳이 동일한 전역 허용 사용자 목록을 공유하며 Tinyauth에 `/var/run/docker.sock`을 마운트하지 않는다. 다른 사용자에게 일부 서비스만 제한적으로 열어야 할 때 서비스별 ACL 도입을 재검토한다.
- **로컬 TOTP 미적용 (D-2):** 로컬 계정의 TOTP(2FA)는 초기 도입 범위에 포함하지 않는다.
- **SOPS `.env` 셸 호환성 (D-5, D-9):** `deploy.sh`와 `healthcheck.sh`가 `.env`를 `set -u` 상태로 source하므로 bcrypt 해시 등 `$` 문자를 포함한 값은 `.env`에서 반드시 작은따옴표(`'...'`)로 감싼다.
- **nginx `--no-deps` 템플릿 호환 (D-1):** `/tinyauth` 및 `auth` 업스트림은 `resolver 127.0.0.11`과 변수 `proxy_pass`를 사용해 `tinyauth` 컨테이너 없이 실행되는 `nginx -t` 검증을 통과해야 한다.
- **수용된 트레이드오프 (D-6, D-8, D-11):** (1) `vps_proxy` 내부 컨테이너 간 네트워크 신뢰, (2) 로컬 계정과 Google 로그인 시 Grafana Admin 계정 분리 생성, (3) `portal`로의 상위 도메인 세션 쿠키 전송, (4) 화이트리스트·계정 변경 시 최대 24시간 세션 유지(긴급 회수 시 세션 DB 볼륨 `vps_tinyauth_data` 삭제로 무효화)를 수용하고 새 ADR Consequences 절에 기록한다.
- **기존 프로젝트 규칙 준수:** `okf/adr/0008`의 `envsubst` 템플릿 구조, `okf/adr/0010`의 SOPS+age 관리, `okf/adr/0016`의 관측 스택 분리 원칙을 따른다.

## Existing code

| Locator | Action | Obligation | Decision |
|---|---|---|---|
| `nginx/templates/erd.conf.template#server` | modify | Basic Auth를 Tinyauth `auth_request` 및 `302` 리다이렉트로 교체 | D-1 |
| `nginx/templates/notes.conf.template#server` | modify | Basic Auth를 Tinyauth `auth_request`로 교체하고 `/404.html` `internal;` 유지 | D-1 |
| `nginx/templates/vps-info.conf.template#server` | modify | Basic Auth를 Tinyauth `auth_request`로 교체 | D-1 |
| `nginx/templates/grafana.conf.template#server` | modify | `/` 및 `/api/live/`에 `auth_request`, `Remote-User` 덮어쓰기, `Authorization ""` 적용 | D-1, D-6 |
| `nginx/templates/health.conf.template#server` | modify | `proxy_set_header Cookie "";`로 세션 쿠키 반사 차단 | D-1 |
| `compose.yml#nginx` | modify | `basic-auth.htpasswd` 마운트 제거 및 `tinyauth` 서비스·`vps_tinyauth_data` 볼륨 추가 | D-5, D-8 |
| `compose.yml#aliases` | modify | `nginx`의 `vps_proxy` alias에 `auth.${BASE_DOMAIN}` 추가 | D-7 |
| `observability/compose.yml#grafana` | modify | Grafana Auth Proxy 활성화, Admin 자동 가입, 로그인 폼·Basic Auth 비활성화 | D-6 |
| `observability/alloy/config.alloy#probe` | modify | Grafana probe를 `http://grafana:3000/api/health`로 변경하고 `auth` probe 추가 | D-7 |
| `scripts/secrets.sh#TARGETS` | modify | `TARGETS`에서 `basic-auth.htpasswd` 항목 제거 | D-5 |
| `scripts/check-sops.sh#leak` | modify | 평문 검사 대상에서 `secrets/basic-auth.htpasswd` 제거 | D-5 |
| `scripts/test-nginx-templates.sh#basic-auth.htpasswd` | modify | 삭제된 `basic-auth.htpasswd` fixture 마운트 제거 및 `auth` 도메인 포함 검사 | D-5 |
| `.gitignore#basic-auth.htpasswd` | modify | `!nginx/test-fixtures/basic-auth.htpasswd` 예외 제거 | D-5 |
| `.env.example#BASIC_AUTH_HTPASSWD` | modify | `BASIC_AUTH_HTPASSWD` 제거 및 Tinyauth 예시 변수 추가 | D-5 |
| `INFRA.md#basic-auth.htpasswd` | modify | Basic Auth secret 참조를 Tinyauth `.env` 구조로 갱신 | D-5 |
| `scripts/deploy.sh#CHALLENGE_DOMAINS` | reuse | `CHALLENGE_DOMAINS` 기반 certbot `--expand` 경로 그대로 사용 | D-3 |
| `scripts/deploy.sh#TLS_MODE` | modify | `BASIC_AUTH_HTPASSWD` 가드를 빈 `TINYAUTH_AUTH_USERS`·로컬 테스트 계정·빈 화이트리스트 및 따옴표 없는 `$` 가드로 교체 | D-5, D-9, D-10 |
| `scripts/test-routing.sh#check` | modify | `curl --resolve` 기반 미인증(302)·로그인 쿠키 발급·보호 경로/정적 자산/Grafana 통과 검증 | D-9 |
| `scripts/healthcheck.sh#check_public_route` | modify | `auth.${BASE_DOMAIN}` 공개 헬스, `grafana:3000/api/health` 내부 헬스, 보호 라우트 `302` 검증 추가 | D-7 |
| `okf/services/nginx.md#개요` | modify | 라우팅 목록(`auth`)과 인증 방식(Tinyauth) 갱신 | D-11 |
| `okf/services/erd.md#접근` | modify | Basic Auth 설명을 Tinyauth로 갱신 | D-11 |
| `okf/adr/0010-sops-secrets.md#결정` | modify | 암호화 대상에서 `basic-auth.htpasswd` 제거 반영 | D-11 |

## Seams & test plan

- **nginx 템플릿 문법 검증** (`example`), AC-1, AC-5, AC-9: `./scripts/test-nginx-templates.sh`로 `none`/`live` 양 모드 렌더링과 `nginx -t`를 검증한다. 놓치는 것: 런타임 쿠키·백엔드 연동.
- **SOPS 무결성 검증** (`example`), AC-8: `./scripts/check-sops.sh` 및 `scripts/secrets.sh decrypt`로 단일화된 `.env` 복호화와 평문 미추적을 검증한다. 놓치는 것: 실제 운영 키 유무.
- **로컬 라우팅·쿠키 E2E 검증** (`e2e`), AC-1, AC-2, AC-3, AC-5, AC-6, AC-7, AC-9, AC-12: `TLS_MODE=none`으로 스택 기동 후 `curl --resolve` 기반 `scripts/test-routing.sh`로 보호 4곳 미인증 `302`, `/tinyauth` 외부 접근 차단(`404`/내부 전용), `X-Forwarded-Host`·`Remote-User` 스푸핑 차단, `health` 쿠키 미반사, 로컬 로그인 쿠키로 `erd`·`notes`·`info`·`grafana` 통과 및 재기동 후 세션 유지를 검증한다. 놓치는 것: Google OAuth 실연동.
- **배포 가드·헬스체크 검증** (`example`), AC-10, AC-11: `deploy.sh`에 잘못된 `.env`(빈 `TINYAUTH_AUTH_USERS`, 로컬 테스트 계정, 빈 화이트리스트, 따옴표 없는 `$`)를 넣은 실패 케이스와 정상 `healthcheck.sh` 실행(`auth` 공개 헬스, 내부 `grafana:3000/api/health`, 보호 라우트 `302`)으로 검증한다. 놓치는 것: 실제 Let's Encrypt 서버 발급.
- **Google OAuth 및 운영 배포 수동 검증** (`manual`), AC-3, AC-4, AC-10, AC-11: 운영 VPS 배포 후 브라우저에서 `auth.kkh-hub.tech` Google OAuth 화이트리스트 허용 계정 성공 및 비허용 계정 거부를 확인하고 `evidence.md`에 기록한다.
- **OKF strict validation** (`example`), AC-13: OKF validator를 실행해 새 ADR(`0022-...`)과 갱신된 OKF 문서의 strict validation 통과를 검증한다.

## Out of scope

- 서비스별 개별 접근 제어(ACL) 및 Tinyauth `/var/run/docker.sock` 마운트 (D-4, 향후 필요 시 별도 스펙으로 도입)
- 로컬 계정 TOTP(2FA) 활성화 (D-2)
- Tailscale 내부망 격리 또는 Tailscale 인증 연동 (후속 보안 강화 단계에서 별도 진행)
- `portal` 애플리케이션 자체의 사용자 인증/권한 기능
