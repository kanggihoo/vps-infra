---
type: ArchitectureProposal
title: 서비스 포털 대시보드 후보 아키텍처
description: React+nginx 포털 UI와 Go net/http 기반 경량 상태 API를 Traefik 뒤에 배치하는 후보 구조.
tags: [architecture, portal, dashboard, react, nginx, go, traefik]
timestamp: 2026-07-01T00:00:00+09:00
---

# 상태

이 문서는 확정 결정이 아니다. Hostinger VPS 1대에서 여러 서비스를 운영할 때, 공통 서비스 포털과 상태 조회 기능을 어떤 구조로 둘지 검토한 후보 아키텍처다.

# 목표

- VPS 안에서 운영 중인 public 서비스를 한 화면에서 빠르게 이동한다.
- 각 서비스의 health 상태를 같은 화면에서 확인할 수 있게 한다.
- PostgreSQL, Redis 같은 내부 데이터 서비스는 외부에 직접 노출하지 않는다.
- 특정 앱 backend에 운영 포털 책임을 얹지 않는다.
- [Traefik 리버스 프록시](/services/traefik.md)를 public HTTP/HTTPS 진입점으로 유지한다.

# 제안 구조

```txt
Internet
  -> DNS: portal.kkh-hub.tech
    -> VPS
      -> Traefik :443
        -> /        -> portal-ui container
        -> /api/*   -> portal-api container
```

서비스별 책임은 다음처럼 나눈다.

| 구성요소 | 책임 |
|----------|------|
| `portal-ui` | React 대시보드 정적 파일 제공, 서비스 카드와 링크 표시 |
| `portal-api` | 서비스 health, PostgreSQL ping, Redis ping 같은 운영 상태 수집 |
| `Traefik` | TLS, hostname/path routing, 인증 middleware 적용 |
| 각 앱 backend | 자기 서비스 기능과 자기 `/health` endpoint 제공 |

# React+nginx 조합

`portal-ui`는 Vite React 같은 SPA를 build한 뒤 nginx가 정적 파일로 제공하는 형태를 후보로 둔다.

```txt
React source
  -> npm run build
    -> dist/
      -> nginx container
        -> index.html, JS, CSS 제공
```

nginx를 쓰는 이유는 React app을 실행하기 위해서가 아니라, build된 정적 파일을 안정적으로 제공하기 위해서다. Traefik은 요청을 어느 container로 보낼지 결정하는 reverse proxy이고, React 정적 파일을 application asset으로 제공하는 역할은 `portal-ui`가 맡는다.

장점:

- 메모리 사용량이 작고 운영 패턴이 단순하다.
- React 화면과 정적 asset 제공 책임이 명확하다.
- Traefik 뒤 내부 container로만 동작하므로 public port를 추가로 열지 않는다.
- 서비스 목록을 `services.json` 같은 runtime config로 빼면 React rebuild 없이 목록을 바꿀 수 있다.

제약:

- React만으로 Docker internal network, PostgreSQL, Redis, VPS host metric을 직접 조회할 수 없다.
- 브라우저에서 실행되는 JavaScript는 public HTTP(S) endpoint만 호출할 수 있다.
- 내부 상태 조회는 별도 backend가 필요하다.

# Go net/http 기반 portal-api

`portal-api`는 Go 표준 라이브러리 `net/http` 기반의 작은 backend를 후보로 둔다.

Go `net/http`를 선택하는 이유:

- API가 `GET /api/status` 같은 소수 endpoint면 framework가 거의 필요 없다.
- single binary 배포가 가능하고 runtime dependency가 작다.
- idle memory가 낮아 작은 VPS에 부담이 적다.
- Docker image를 작게 만들 수 있다.
- 상태 수집 서버는 복잡한 web framework 기능보다 timeout, 병렬 health check, 명확한 JSON 응답이 더 중요하다.

`portal-api`가 필요한 이유:

- React는 사용자 브라우저에서 실행되므로 Docker network 내부 hostname에 접근할 수 없다.
- PostgreSQL과 Redis는 HTTP 서비스가 아니므로 `fetch()`로 직접 조회할 수 없다.
- VPS CPU/RAM/disk 같은 host 상태는 서버 쪽 코드가 수집해 JSON으로 노출해야 한다.
- 특정 앱 backend가 운영 포털 역할까지 맡으면 앱 장애나 배포가 포털 장애로 전파된다.

예상 endpoint:

```txt
GET /api/status
GET /api/services
```

`/api/status` 응답 예:

```json
{
  "services": [
    { "name": "health", "status": "up", "url": "https://health.kkh-hub.tech" },
    { "name": "postgres", "status": "up" },
    { "name": "redis", "status": "up" }
  ]
}
```

# 상태 수집 방식

초기 범위는 낮은 권한으로 가능한 확인만 포함한다.

| 대상 | 수집 방식 | 비고 |
|------|-----------|------|
| public HTTP 서비스 | `GET https://service-domain/health` | 브라우저가 직접 해도 되지만 API가 모아 주면 UI 단순 |
| private HTTP 서비스 | `GET http://service-name:port/health` | 같은 Docker network에 있을 때 가능 |
| PostgreSQL | TCP connect 또는 `pg_isready` 성격의 check | DB password와 timeout 관리 필요 |
| Redis | `PING` | Redis password 필요 |
| VPS CPU/RAM/disk | 보류 | host mount와 권한 설계 후 진행 |

Docker socket을 `portal-api`에 직접 mount하는 방식은 초기 후보에서 제외한다. 권한이 너무 넓고, 실수 시 host 제어 권한이 노출될 수 있다.

# Traefik 라우팅

같은 hostname 아래에서 UI와 API를 path로 나눌 수 있다.

```txt
Host(`portal.kkh-hub.tech`) && PathPrefix(`/api`)
  -> portal-api

Host(`portal.kkh-hub.tech`)
  -> portal-ui
```

React 화면에서는 상대 경로로 API를 호출한다.

```ts
fetch("/api/status")
```

브라우저 입장에서는 같은 origin 요청이므로 CORS 설정이 단순하다.

# 배포 방식

`portal-ui`와 `portal-api`는 이 인프라 repository 안에서 함께 관리하고, Docker Compose 서비스로 배포하는 후보를 둔다.

```txt
vps-infra/
  compose.yml
  portal-ui/
    Dockerfile
    src/
  portal-api/
    Dockerfile
    cmd/
```

배포는 기존 [GitHub Actions 배포](/services/github-actions-deploy.md) 흐름과 같은 VPS 배포 경로를 사용한다.

```txt
GitHub main
  -> GitHub Actions
    -> SSH
      -> /opt/vps-infra
        -> git pull
        -> docker compose up -d
```

다만 포털 변경이 PostgreSQL, Redis, Traefik까지 불필요하게 건드리지 않도록 workflow 분리를 검토한다.

```txt
infra 변경
  -> 전체 deploy

portal-ui 또는 portal-api 변경
  -> docker compose up -d --build portal-ui portal-api
```

# 보안 원칙

- `portal.kkh-hub.tech`는 관리자용 화면이므로 인증을 붙인다.
- 초기에는 Traefik Basic Auth를 사용할 수 있다.
- 장기적으로는 Traefik SSO 연동 후보와 연결한다.
- PostgreSQL, Redis, Docker socket은 public으로 노출하지 않는다.
- `/api/status` 응답에는 secret, internal URL, 상세 error stack을 포함하지 않는다.

# 대안

| 대안 | 장점 | 단점 |
|------|------|------|
| Vercel React dashboard | VPS 메모리 0, 배포 쉬움 | VPS internal network 조회 불가 |
| Next.js on VPS | UI와 API를 한 서비스로 통합 | nginx+Go보다 메모리 사용량 큼 |
| Uptime Kuma/Netdata | 직접 구현 적음 | 커스텀 포털 화면과 통합성 낮음 |
| 특정 앱 backend에 포털 기능 추가 | 새 서버 없음 | 앱 장애가 운영 포털 장애가 됨 |

# 현재 후보 결론

현재 목표가 "서비스 이동 포털 + 가벼운 상태 확인"이라면 다음 조합이 균형이 좋다.

```txt
portal-ui: React + nginx
portal-api: Go net/http
routing: Traefik
deployment: vps-infra Compose/GitHub Actions
```

이 구조는 Next.js 같은 full-stack framework 없이도 UI와 상태 수집 책임을 분리한다. 동시에 특정 비즈니스 서비스 backend에 운영 책임을 섞지 않는다.

# 관련 개념

- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [Traefik 리버스 프록시](/services/traefik.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [앞으로 할 일](/roadmap/next-work.md)


--- 

# 위의 제한 사항에 대한 리뷰 내용
검토 결과: **방향은 적합합니다.**
특히 [portal-dashboard-proposal.md](/Users/kkh/Desktop/vps/vps-infra/.okf/architecture/portal-dashboard-proposal.md:21)의 `portal-ui + portal-api + Traefik` 분리는 이 VPS 운영 방식과 잘 맞습니다. PostgreSQL/Redis를 외부에 노출하지 않고, Docker socket을 `portal-api`에 mount하지 않겠다는 판단도 맞습니다.

다만 지금 단계에서 가장 현실적인 개선은 **2-container React+nginx + Go API를 바로 만들기보다 더 낮은 단계부터 시작하는 것**입니다.

**추천 순서**

1. **1단계: 단일 Go `portal` 서비스**
   - Go `net/http` 하나가 정적 HTML/CSS/JS와 `/api/status`를 같이 제공.
   - React/nginx 없이 시작.
   - Compose 서비스 1개만 추가.
   - 현재 목표가 “서비스 링크 + 간단한 상태 확인”이면 이게 제일 낮고 운영 부담이 작습니다.

2. **2단계: 화면이 복잡해지면 React+nginx 분리**
   - 카드 필터링, 상태 히스토리, 사용자별 뷰 같은 UI 요구가 생기면 그때 [문서의 구조](/Users/kkh/Desktop/vps/vps-infra/.okf/architecture/portal-dashboard-proposal.md:41)로 분리해도 늦지 않습니다.

3. **3단계: 모니터링/알림은 별도 도구 검토**
   - “대시보드”보다 “장애 알림”이 목적이면 직접 구현보다 Uptime Kuma가 더 적합할 수 있습니다.
   - “운영 포털 + 서비스 링크 + 간단 상태”가 목적이면 커스텀 포털이 맞습니다.

**수정/보강하면 좋은 점**

- `portal-api`는 `proxy`와 `data` 네트워크 양쪽에 붙어야 합니다. 현재 `whoami`는 `proxy`, PostgreSQL/Redis는 `data`에만 있습니다: [compose.yml](/Users/kkh/Desktop/vps/vps-infra/compose.yml:36), [compose.yml](/Users/kkh/Desktop/vps/vps-infra/compose.yml:50), [compose.yml](/Users/kkh/Desktop/vps/vps-infra/compose.yml:69)
- DB/Redis 체크에는 운영 superuser/password를 그대로 쓰지 말고, 가능하면 `portal_monitor` 같은 최소 권한 계정을 두는 게 좋습니다.
- 현재 배포 스크립트는 `docker compose pull` 후 `docker compose up -d --wait`만 합니다: [scripts/deploy.sh](/Users/kkh/Desktop/vps/vps-infra/scripts/deploy.sh:18). 로컬 Dockerfile 기반 `portal-ui`/`portal-api`를 추가하면 `--build` 또는 buildable 서비스 처리 전략이 필요합니다.
- Basic Auth는 UI 라우터뿐 아니라 `/api` 라우터에도 반드시 붙어야 합니다. 문서의 라우팅 구조상 [UI/API router가 분리](/Users/kkh/Desktop/vps/vps-infra/.okf/architecture/portal-dashboard-proposal.md:120)되기 때문입니다.
- “서브도메인 기반 라우팅” 결정과 충돌하지 않도록, `portal.kkh-hub.tech` 자체는 서브도메인이고 그 내부에서만 `/api` path split을 쓴다고 명시하면 좋습니다. 기존 결정은 public service 단위를 서브도메인으로 나누는 쪽입니다: [subdomain-routing.md](/Users/kkh/Desktop/vps/vps-infra/.okf/decisions/subdomain-routing.md:11)

**제 결론**

현재 문서의 최종 후보인 `React + nginx`, `Go net/http`, `Traefik`, `Compose/GitHub Actions`는 장기 구조로 괜찮습니다. 하지만 지금 VPS 운영 초기라면 **단일 Go portal 서비스로 시작**하는 쪽이 더 낮고, 실패 지점도 적습니다. 이후 UI 요구가 커졌을 때 React+nginx로 분리하는 게 가장 실용적인 경로입니다.