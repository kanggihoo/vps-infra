---
type: ArchitectureProposal
title: 공용 인프라 포털 MVP 아키텍처
description: 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털 MVP 구조.
tags: [architecture, portal, dashboard, react, go, traefik, skills, tailwind, shadcn]
timestamp: 2026-07-03T00:00:00+09:00
---

# 상태

이 문서는 확정 구현이 아니라 MVP 설계 기준이다. 기존 장기 후보였던
`React+nginx + Go API + 운영 상태 수집` 구조에서 범위를 줄여, 첫 버전은 현재
repository에 구현된 public service 링크와 skill markdown library만 제공한다.

# 목표

- VPS 안에서 실제 운영 중인 public service entrypoint를 빠르게 이동한다.
- 자주 쓰는 agent skill 원문을 보기 쉽게 렌더링하고 복사할 수 있게 한다.
- 포털을 특정 앱 backend에 얹지 않고 인프라 repository에서 관리한다.
- [Traefik 리버스 프록시](/services/traefik.md)를 public HTTP/HTTPS 진입점으로 유지한다.

# MVP 범위

포털 첫 버전은 두 화면만 포함한다.

```txt
Portal
  Services
  Skills
```

포함한다.

- 현재 코드상 구현된 public route 링크.
- `traefik.kkh-hub.tech` Traefik dashboard 링크.
- `health.kkh-hub.tech` whoami health route 링크.
- 자주 쓰는 skill markdown 원문 viewer.
- skill frontmatter metadata 표시.
- markdown rendered preview.
- raw markdown 보기.
- 원문 전체, body, install command 복사.

제외한다.

- API 사용량 수집.
- server CPU/RAM/disk 상태 수집.
- PostgreSQL/Redis 상태 조회.
- uptime history.
- 장애 알림.
- skill 추가/삭제/수정 UI.
- 런타임 `~/.codex` 또는 `~/.agents` directory scan.
- Docker socket mount.
- 별도 DB 저장.

# 제안 구조

```txt
Internet
  -> DNS: portal.kkh-hub.tech
    -> VPS
      -> Traefik :443
        -> portal Go service
          -> React static files
          -> static skill markdown files
```

`portal` service는 Go `net/http` 기반으로 React build output과 curated skill markdown
파일을 제공한다. React UI는 Tailwind CSS v4, shadcn/ui, lucide-react, Pretendard를 사용한다.
UI theme은 `portal/DESIGN-mintlify.md`의 dark documentation surface를 기준으로 하며,
dark mode를 기본값으로 사용한다.
Traefik이 TLS와 hostname routing을 맡으므로 별도 nginx container는 초기 범위에서 사용하지 않는다.

# Services 화면

Services 화면은 실제 구현된 public entrypoint만 보여준다.

| 항목 | URL | 설명 |
|------|-----|------|
| Traefik dashboard | `https://traefik.kkh-hub.tech` | Basic Auth 보호된 reverse proxy dashboard |
| Health/whoami | `https://health.kkh-hub.tech` | DNS/TLS/Traefik routing 검증용 public endpoint |
| Repository | GitHub repository URL | 인프라 코드 진입점 |

후보 route나 아직 배포되지 않은 다른 project 링크는 표시하지 않는다. 다른 project가 실제로
Compose와 Traefik label에 추가된 뒤 포털 항목도 늘린다.

# Skills 화면

Skills 화면은 작은 read-only markdown library다.

```txt
portal/skills/index.yml
portal/skills/*.md
```

각 skill item은 frontmatter가 있는 markdown 원문을 유지한다. 화면은 frontmatter metadata,
rendered markdown preview, raw markdown tab을 분리해 보여준다.

복사 기능은 다음 세 가지를 제공한다.

- `Copy original`: frontmatter 포함 전체 markdown.
- `Copy body`: frontmatter 제외 body markdown.
- `Copy install command`: `index.yml`에 기록한 설치 명령.

각 skill은 source GitHub URL을 가질 수 있다. 상세 화면 상단에는 source 링크를 보여주고,
install command는 screenshot-style dark command block으로 분리해 복사한다.

skill item은 10개 이하 curated list로 시작한다. 추가/삭제는 UI가 아니라 Git 변경으로 한다.
UI 기반 CRUD는 file write 권한, audit, 실수 삭제, 인증 강도 문제를 만들기 때문에 MVP에서
제외한다.

# 책임 경계

| 책임 | 위치 |
|------|------|
| public route/TLS/auth | Traefik |
| 포털 static file serving | `portal` Go service |
| 서비스 링크 정의 | `portal/public/config/services.json` 또는 OKF/Compose에서 파생 |
| skill 원문 | `portal/skills/*.md` curated copy |
| skill list/install command | `portal/skills/index.yml` |
| 운영 관측/알림 | MVP 제외, 나중 단계 |

# 보안 원칙

- 현재 MVP는 public service link와 공개 가능한 skill 원문만 제공하므로 `portal.kkh-hub.tech`에 Basic Auth를 붙이지 않는다.
- runtime host의 `~/.codex`, `~/.agents`, `.env`, private key, token 파일을 읽지 않는다.
- 포털이 제공하는 skill source는 repository에 포함 가능한 curated copy로 제한한다.
- markdown render 시 raw HTML은 비활성화하거나 sanitize한다.
- PostgreSQL, Redis, Docker socket은 포털 container에 노출하지 않는다.
- 나중에 status, logs, metrics, deploy action 같은 운영 기능을 추가하면 인증을 다시 적용한다.

# 배포 고려사항

포털 추가 시 Compose service는 `proxy` network에만 연결한다. DB/Redis 상태를 조회하지 않으므로
`data` network 연결은 필요 없다.

```txt
portal
  build: ./portal
  networks:
    - proxy
```

local Dockerfile build가 생기므로 [GitHub Actions 배포](/services/github-actions-deploy.md)
흐름에서 buildable service 처리 전략을 정해야 한다. 현재 배포 script가 `docker compose pull`
뒤 `docker compose up -d --wait`를 실행하므로, 포털 구현 시 `--build` 적용 여부를 함께
수정한다.

# 나중 단계

- Services 항목을 `compose.yml` 또는 OKF에서 생성.
- Status 화면 추가.
- API 사용량 요약.
- 외부 service health check.
- skill sync script 추가.
- favorites/tag filter 추가.
- SSO 전환.

# 관련 설계 문서

- `docs/superpowers/specs/2026-07-03-portal-services-skills-mvp-design.md`

# 관련 개념

- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [Traefik 리버스 프록시](/services/traefik.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)
