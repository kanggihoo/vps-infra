---
type: Service
title: 공용 인프라 포털
description: 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
tags: [portal, react, go, traefik, skills]
timestamp: 2026-07-03T00:00:00+09:00
---

# 개요

공용 인프라 포털은 Hostinger VPS 공통 인프라의 관리자용 entrypoint다.
[Traefik 리버스 프록시](/services/traefik.md) 뒤에서 `portal.kkh-hub.tech`로 노출되며,
현재 구현된 public service 링크와 자주 쓰는 skill markdown 원문을 보여준다.

# Route

```txt
https://portal.kkh-hub.tech -> portal
```

# 구현

`portal`은 Go `net/http` 서버 하나로 동작한다. Vite React build 결과물과 curated skill
markdown 파일을 정적 파일로 제공한다.

```txt
portal/
  cmd/portal/
  src/
  public/config/services.json
  public/skills/
```

# 범위

포함한다.

- Services 화면.
- Skills 화면.
- skill frontmatter 표시.
- markdown preview.
- raw markdown 보기.
- 원문/body/install command 복사.

제외한다.

- API 사용량 수집.
- server health 수집.
- PostgreSQL/Redis 상태 조회.
- 런타임 host skill directory scan.
- skill CRUD.

# 보안

- Traefik Basic Auth를 적용한다.
- `proxy` network에만 연결한다.
- PostgreSQL, Redis, Docker socket을 연결하지 않는다.
- skill 원문은 repository에 포함 가능한 curated copy만 제공한다.

# 관련 개념

- [공용 인프라 포털 MVP 아키텍처](/architecture/portal-dashboard-proposal.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)

