# Agent Instructions

정확하고 명확하게 응답한다.

## 필수 컨텍스트

- 이 repository는 Hostinger VPS 1대의 공통 인프라를 관리한다.
- 작업 전 `.okf/index.md`를 먼저 읽고, 관련 개념 문서를 따라간다.
- 설계 원본은 `docs/superpowers/specs/2026-06-28-vps-infra-github-actions-design.md`다.
- 쉘 명령은 `/Users/kkh/.codex/RTK.md` 기준으로 가능하면 `rtk`를 사용한다.

## 현재 방향

- Runtime: Docker Compose
- Reverse proxy: Traefik
- Deploy: GitHub Actions -> SSH -> VPS `git pull` -> `docker compose up -d`
- Initial routes:
  - `traefik.kkh-hub.tech` -> Traefik dashboard + Basic Auth
  - `health.kkh-hub.tech` -> `traefik/whoami`
- Data services:
  - PostgreSQL 1 container, public port 미노출
  - Redis 1 container, public port 미노출

## 보안 규칙

- `.env`, private key, DB password, Redis password, Traefik Basic Auth hash는 Git에 커밋하지 않는다.
- public 운영 메타데이터만 OKF에 기록한다.
- PostgreSQL/Redis는 외부 port publish 하지 않는다.
- Traefik만 `80/443` public port를 소유한다.

## OKF 사용

- durable project knowledge는 `.okf/`에 한국어로 기록한다.
- OKF concept는 파일 하나당 개념 하나로 유지한다.
- OKF 수정 후 strict validation을 실행한다.
