# Tinyauth SSO decisions

Glossary: none · ADRs: [0008](../../adr/0008-nginx-env-templates.md), [0010](../../adr/0010-sops-secrets.md), [0016](../../adr/0016-self-hosted-observability.md)

## D-1 Protected subdomain scope
- Status: settled
- Decision: `erd`, `notes`, `info`, `grafana` 4곳을 Tinyauth forward-auth로 보호하고 `portal`·`health`는 공개로 유지한다. `/tinyauth` subrequest는 `--no-deps` `nginx -t` 통과를 위해 `resolver 127.0.0.11`과 변수 upstream을 쓰고, `notes`의 `/404.html`은 `internal;`을 유지하며, `health`는 `whoami`에 세션 쿠키가 반사되지 않도록 `Cookie` 헤더를 빈 값으로 덮어쓴다.
- Rejected: `grafana`를 기존 자체 로그인으로 유지 → 단일 SSO 세션으로 운영 일관성을 맞추기 위해 통합
- Reuse: `nginx/templates/erd.conf.template#server` (modify) — Basic Auth를 Tinyauth `auth_request`로 교체 · `nginx/templates/notes.conf.template#server` (modify) — Basic Auth를 Tinyauth `auth_request`로 교체하고 `/404.html` `internal;` 유지 · `nginx/templates/vps-info.conf.template#server` (modify) — Basic Auth를 Tinyauth `auth_request`로 교체 · `nginx/templates/grafana.conf.template#server` (modify) — `/` 및 `/api/live/` WebSocket에 Tinyauth `auth_request`와 `Remote-User` 헤더 전달 적용 · `nginx/templates/health.conf.template#server` (modify) — `proxy_set_header Cookie "";`로 세션 쿠키 반사 차단

## D-2 Authentication methods and OAuth whitelist
- Status: settled
- Decision: 로컬 계정(ID/PW)과 Google OAuth를 동시 지원하며, Google OAuth는 허용 이메일 화이트리스트를 필수로 적용한다. 로컬 TOTP(2FA)는 초기 도입에서 미적용한다.
- Rejected: 로컬 ID/PW 단독 사용 → 향후 외부/모바일 접근성과 보안 확장성 부족 · 화이트리스트 없는 Google OAuth → 임의의 Google 계정 통과 위험

## D-3 Login portal subdomain
- Status: settled
- Decision: Tinyauth 로그인 포털은 `auth.${BASE_DOMAIN}`(운영 `auth.kkh-hub.tech`, 로컬 `auth.vps.localhost`)으로 고정하고, 운영 TLS 인증서는 `CHALLENGE_DOMAINS`에 추가해 certbot `--expand`로 발급한다(DNS A 레코드는 운영자가 등록). 로컬 `BASE_DOMAIN`은 `vps.localhost`다.
- Rejected: 로컬 `BASE_DOMAIN=localhost` 유지 → Tinyauth v5가 `localhost`를 TLD로 보고 쿠키를 `Domain=auth.localhost`로 발급해, `erd.localhost` 확인이 `domain does not match cookie domain`으로 500이 된다(2026-11-27 v5.2.0 실측)
- Reuse: `scripts/deploy.sh#CHALLENGE_DOMAINS` (reuse) — `CHALLENGE_DOMAINS` 기반 certbot `--expand` 경로 그대로 사용

## D-4 Access control granularity
- Status: provisional
- Decision: 보호 대상 4곳이 동일한 전역 허용 사용자 목록을 공유하며 Tinyauth에 `/var/run/docker.sock`을 마운트하지 않는다.
- Default: 모든 보호 대상이 동일한 전역 허용 목록을 공유하고 `docker.sock`을 마운트하지 않는다; 다른 사용자에게 일부 서비스만 제한적으로 열어야 할 때 서비스별 ACL을 재검토한다.
- Rejected: 초기부터 Docker label 기반 서비스별 ACL 적용 → `docker.sock` 마운트 권한 노출 및 초기 복잡도 증가

## D-5 Secret consolidation and Basic Auth retirement
- Status: settled
- Decision: `secrets/basic-auth.htpasswd.sops.txt`, `nginx/test-fixtures/basic-auth.htpasswd`, `scripts/set-basic-auth.sh` 및 관련 참조를 제거하고 Tinyauth 설정을 `secrets/env.{local,prod}.sops.env`로 단일화한다. `deploy.sh`/`healthcheck.sh`가 `.env`를 `set -u`로 source하므로 bcrypt `$` 포함 값은 작은따옴표(`'...'`)로 감싼다.
- Rejected: 별도 SOPS 인증 파일·`USERS_FILE` 유지 → 암호화 대상과 복호화/관리 스크립트가 불필요하게 이원화됨
- Reuse: `scripts/secrets.sh#TARGETS` (modify) — `basic-auth.htpasswd` 항목 제거 · `compose.yml#nginx` (modify) — `basic-auth.htpasswd` 마운트 제거 및 `tinyauth` 서비스 추가 · `scripts/test-nginx-templates.sh#basic-auth.htpasswd` (modify) — fixture 마운트 제거 · `scripts/check-sops.sh#leak` (modify) — 평문 검사 대상에서 `basic-auth.htpasswd` 제거 · `.gitignore#basic-auth.htpasswd` (modify) — 예외 규칙 제거 · `.env.example#BASIC_AUTH_HTPASSWD` (modify) — Tinyauth 환경변수 예시로 교체 · `INFRA.md#basic-auth.htpasswd` (modify) — secret 목록 갱신

## D-6 Grafana Auth Proxy SSO
- Status: settled
- Decision: Grafana는 `GF_AUTH_PROXY_ENABLED=true`, `GF_AUTH_DISABLE_LOGIN_FORM=true`, `GF_AUTH_BASIC_ENABLED=false`로 `Remote-User` 기반 Admin 자동 로그인만 허용한다. nginx는 `/`와 `/api/live/` 모두에서 `Remote-User`를 `auth_request_set` 값으로 강제 덮어쓰고 `Authorization` 헤더를 `""`로 비운다. (`vps_proxy` 내부 컨테이너 신뢰 및 로컬/Google 이중 계정은 수용된 트레이드오프다.)
- Rejected: Grafana 자체 로그인 유지 → 별도 계정/비밀번호 이중 관리 발생
- Reuse: `observability/compose.yml#grafana` (modify) — Auth Proxy 활성화 및 로그인 폼·Basic Auth 비활성화

## D-7 Healthcheck and observability probes
- Status: settled
- Decision: Alloy의 Grafana blackbox probe는 내부 주소(`http://grafana:3000/api/health`)로 변경하고, Alloy 상시 probe와 `scripts/healthcheck.sh`에 `auth.${BASE_DOMAIN}` 공개 헬스체크를 추가한다. `healthcheck.sh`는 Grafana 실제 생존을 내부 헬스(`http://grafana:3000/api/health`)로 확인하고, 보호 라우트 요청이 `auth.${BASE_DOMAIN}`으로 302 리다이렉트되는지 검증한다.
- Rejected: Grafana `/api/health`만 외부 인증 예외로 개방 → 보호 서브도메인의 무인증 예외 경로를 남기지 않기 위함
- Reuse: `observability/alloy/config.alloy#probe` (modify) — Grafana probe 내부 주소 변경 및 `auth` probe 추가 · `scripts/healthcheck.sh#check_public_route` (modify) — `auth` 헬스체크, 보호 라우트 302 검증, Grafana 내부 헬스 확인 추가 · `compose.yml#aliases` (modify) — `vps_proxy` alias에 `auth.${BASE_DOMAIN}` 추가

## D-8 Session persistence and lifetime
- Status: settled
- Decision: Tinyauth 세션 DB(SQLite)는 named volume(`vps_tinyauth_data`)에 영속 저장하고, 세션 만료 시간은 24시간(1일)으로 고정한다. (상위 도메인 쿠키의 `portal` 전송과 화이트리스트 변경 후 최대 24시간 세션 유지는 수용된 트레이드오프이며, 긴급 회수 시 세션 DB 볼륨을 삭제해 모든 세션을 무효화한다.)
- Rejected: 7일 장기 세션 → 세션 노출 기간이 길어짐 · 비영속 저장 → 재배포마다 강제 로그아웃 · 서명 시크릿(`TINYAUTH_SECRET`) 교체로 세션 무효화 → Tinyauth v5는 쿠키에 무작위 세션 ID만 담고 DB로 검증해 secret 설정이 없다

## D-9 Cookie-session verification and environment guards
- Status: settled
- Decision: 인증 검증은 브라우저 쿠키 세션 경로를 기준으로 하며 `test-routing.sh`는 로컬 `curl --resolve <host>:80:127.0.0.1`로 쿠키를 발급·검증한다. 로컬(`TLS_MODE=none`)은 Google OAuth 없이 테스트 계정만으로 통과하고, 운영(`TLS_MODE=live`)은 빈 `TINYAUTH_AUTH_USERS`·로컬 테스트 계정·빈 OAuth 화이트리스트 및 `.env`의 따옴표 없는 `$` 값을 감지해 배포를 차단한다.
- Rejected: `curl -u` Basic Auth 헤더 기반 테스트 유지 → 실제 브라우저 쿠키 세션 경로를 검증하지 못함
- Reuse: `scripts/test-routing.sh#check` (modify) — `--resolve` 기반 Tinyauth 미인증(302) 및 로그인 쿠키 세션 통과 검증으로 교체 · `scripts/deploy.sh#TLS_MODE` (modify) — Tinyauth 계정·테스트 계정·화이트리스트 및 따옴표 없는 `$` 가드 적용

## D-10 Security invariants
- Status: settled
- Decision: 다음 4가지는 절대 허용하지 않는다: (1) 빈 Google OAuth 화이트리스트로 임의 계정이 통과하는 것, (2) `TLS_MODE=live`에서 로컬 테스트 계정이나 빈 계정 목록으로 기동되는 것, (3) 보호 서브도메인의 `/tinyauth` subrequest가 `internal;` 없이 외부에 노출되거나, `X-Forwarded-Host`(`$host`)·`Remote-User`(Tinyauth 결과) 덮어쓰기 누락으로 인증이 우회되는 것, (4) 보호 대상 4곳(`erd`, `notes`, `info`, `grafana`)의 어떤 경로(정적 자산·WebSocket·`/404.html` 포함)도 미인증 요청에 200을 반환하는 것.

## D-11 ADR and OKF documentation
- Status: settled
- Decision: Basic Auth → Tinyauth 전환에 대한 새 ADR(`okf/adr/0022-...`)을 추가하고 관련 OKF 문서를 갱신해 OKF strict validation을 통과시킨다. 새 ADR의 결과(Consequences) 절에는 수용된 트레이드오프 4건(`vps_proxy` 내부 신뢰, 로컬/Google 이중 Grafana 계정, `portal` 상위 도메인 쿠키 전송, 최대 24시간 세션 회수 지연)을 기록한다.
- Reuse: `okf/services/nginx.md#개요` (modify) — 라우팅·인증 방식 갱신 · `okf/services/erd.md#접근` (modify) — Basic Auth 설명을 Tinyauth로 갱신 · `okf/adr/0010-sops-secrets.md#결정` (modify) — 암호화 대상에서 `basic-auth.htpasswd` 제거 반영
