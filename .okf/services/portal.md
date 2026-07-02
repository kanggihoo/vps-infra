---
type: Service
title: 공용 인프라 포털
description: 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
tags: [portal, react, go, traefik, skills, tailwind, shadcn]
timestamp: 2026-07-03T00:00:00+09:00
---

# 개요

공용 인프라 포털은 Hostinger VPS 공통 인프라의 공개 entrypoint다.
[Traefik 리버스 프록시](/services/traefik.md) 뒤에서 `portal.kkh-hub.tech`로 노출되며,
현재 구현된 public service 링크와 자주 쓰는 skill markdown 원문을 보여준다.

# Route

```txt
https://portal.kkh-hub.tech -> portal
```

# 구현

`portal`은 Go `net/http` 서버 하나로 동작한다. Vite React build 결과물과 curated skill
markdown 파일을 정적 파일로 제공한다. Frontend는 Tailwind CSS v4, shadcn/ui, lucide-react,
Pretendard 기반으로 구성한다.

```txt
portal/
  main.go
  src/
    components/ui/
    lib/utils.ts
  public/config/services.json
  public/skills/
  components.json
```

# Frontend UI stack

- Vite React + TypeScript.
- Tailwind CSS v4 with `@tailwindcss/vite`.
- shadcn/ui radix-nova preset with CSS variables.
- lucide-react icons.
- Pretendard font via `@fontsource/pretendard`.
- Mintlify-inspired dark documentation surface from `portal/DESIGN-mintlify.md`.
- Dark mode is the default theme; light mode is available from the top bar.

# 배포

`portal/` 아래 파일만 변경된 push는 GitHub Actions가 `./scripts/deploy.sh portal`을
실행한다. 이 경로는 포털 image만 rebuild하고 `--no-deps`로 다른 Compose service 재생성을
피한다.

```txt
docker compose up -d --build --no-deps portal
```

`compose.yml`, Traefik, DB, Redis, 배포 script 같은 인프라 파일이 함께 변경되면 전체
배포 경로를 사용한다.

# 범위

포함한다.

- Services 화면.
- Skills 화면.
- skill frontmatter 표시.
- markdown preview.
- raw markdown 보기.
- 원문/body/install command 복사.
- skill source GitHub URL 표시와 외부 이동.
- install command를 별도 command block으로 표시하고 복사.

제외한다.

- API 사용량 수집.
- server health 수집.
- PostgreSQL/Redis 상태 조회.
- 런타임 host skill directory scan.
- skill CRUD.

# 보안

- 현재 MVP는 이미 공개 가능한 service link와 public skill 원문만 제공하므로 Basic Auth를 적용하지 않는다.
- `proxy` network에만 연결한다.
- PostgreSQL, Redis, Docker socket을 연결하지 않는다.
- skill 원문은 repository에 포함 가능한 curated copy만 제공한다.
- 나중에 status, logs, metrics, deploy action 같은 운영 기능을 추가하면 인증을 다시 적용한다.

# 관련 개념

- [공용 인프라 포털 MVP 아키텍처](/architecture/portal-dashboard-proposal.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
