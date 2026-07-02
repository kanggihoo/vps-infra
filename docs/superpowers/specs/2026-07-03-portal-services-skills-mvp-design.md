# 공용 인프라 포털 MVP 설계

## 목적

Hostinger VPS 공통 인프라에서 운영 중인 public entrypoint를 빠르게 찾고,
자주 쓰는 agent skill 원문을 보기 쉽게 확인한 뒤 복사할 수 있는 작은 포털을 만든다.

첫 버전은 monitoring dashboard가 아니다. API 사용량, server health, PostgreSQL/Redis 상태,
alerting은 제외한다. 현재 repository에 실제로 구현된 서비스와 curated skill 문서만 보여준다.

## 범위

### 포함

- `portal.kkh-hub.tech` public route.
- Traefik 뒤의 단일 Go `portal` service.
- Go `net/http` 기반 static file serving.
- Vite React build 결과물 제공.
- Services 화면.
- Skills 화면.
- skill markdown frontmatter 표시.
- skill markdown body rendered preview.
- raw markdown 보기.
- 원문 전체 복사.
- body만 복사.
- install command 복사.

### 제외

- API 사용량 수집.
- server CPU/RAM/disk 상태 수집.
- PostgreSQL/Redis 상태 조회.
- uptime history.
- 장애 알림.
- skill 추가/삭제/수정 UI.
- 런타임 `~/.codex` 또는 `~/.agents` directory scan.
- Docker socket mount.
- 별도 DB 저장.
- Next.js SSR.

## 아키텍처

```txt
Internet
  -> DNS: portal.kkh-hub.tech
    -> VPS
      -> Traefik :443
        -> portal Go service
          -> React static files
          -> static skill markdown files
```

Traefik은 TLS와 hostname routing을 맡는다. nginx는 쓰지 않는다. Go service가
React build output과 curated skill markdown 파일을 정적 파일로 제공한다.

첫 버전에는 backend business API가 필요 없다. Go는 배포 단위를 단순하게 만들기 위한
static server 역할이다. 나중에 동적 service registry가 필요해지면 `/api/services`를
추가할 수 있다.

## 화면 구조

```txt
Portal
  Services
  Skills
```

`Status` 화면은 만들지 않는다. 2번 운영 관측 범위는 다음 단계로 남긴다.

## Services 화면

Services 화면은 현재 코드상 구현된 public route와 운영 링크만 보여준다.

초기 항목:

| 항목 | URL | 설명 |
|------|-----|------|
| Traefik dashboard | `https://traefik.kkh-hub.tech` | Basic Auth 보호된 reverse proxy dashboard |
| Health/whoami | `https://health.kkh-hub.tech` | DNS/TLS/Traefik routing 검증용 public endpoint |
| Repository | GitHub repository URL | 인프라 코드 진입점 |

데이터 원본은 처음에는 정적 config로 둔다.

```txt
portal/config/services.yml
```

Services 화면은 다른 project onboarding이 실제로 끝난 뒤에만 항목을 늘린다. 아직 배포되지
않은 후보 route는 표시하지 않는다.

## Skills 화면

Skills 화면은 10개 이하의 자주 쓰는 skill 원문을 read-only로 보여주는 library다.

데이터 원본:

```txt
portal/skills/index.yml
portal/skills/*.md
```

`index.yml`은 list, 표시 이름, 설명, 설치 명령, tag, 원문 path를 관리한다.

```yaml
- id: caveman
  title: caveman
  path: /skills/caveman.md
  install_command: "npx skills install caveman"
  tags: [style, prompt]
```

각 skill markdown은 원본 형식을 유지한다.

```md
---
name: caveman
description: Ultra-compressed communication mode.
---

# Skill body
```

UI는 frontmatter와 body를 분리해 보여준다.

- frontmatter: metadata panel.
- body: markdown rendered preview.
- raw: 원문 markdown tab.
- `Copy original`: frontmatter 포함 전체 markdown 복사.
- `Copy body`: frontmatter 제외 body만 복사.
- `Copy install command`: 설치 명령 복사.

clipboard 기능은 HTTPS 환경과 사용자 click event를 전제로 `navigator.clipboard.writeText`
를 사용한다. 실패하면 raw textarea를 선택해 수동 복사할 수 있게 한다.

## 추가/삭제 정책

첫 버전에서 skill item 추가/삭제는 UI가 아니라 Git 변경으로 처리한다.

```txt
추가:
  portal/skills/*.md 추가
  portal/skills/index.yml 수정
  commit
  deploy

삭제:
  portal/skills/index.yml에서 제거
  필요하면 md 파일 삭제
  commit
  deploy
```

이 방식은 file write 권한, admin CRUD, audit log, 실수 삭제 방지 같은 문제를 만들지 않는다.
Git history가 변경 이력 역할을 한다.

## 보안

- `portal.kkh-hub.tech`는 관리자용 화면이므로 Traefik Basic Auth를 붙인다.
- skill 원문은 curated copy만 제공한다.
- 런타임에 host의 `~/.codex`, `~/.agents`, `.env`, private key, token 파일을 읽지 않는다.
- clipboard에 secret이 들어가지 않도록 skill source는 repository에 포함 가능한 내용만 둔다.
- raw HTML markdown rendering은 비활성화하거나 sanitize한다.

## 배포

새 Compose service를 추가한다.

```txt
portal
  build: ./portal
  networks:
    - proxy
```

Traefik label은 `portal.kkh-hub.tech` hostname만 사용한다. 기존 서브도메인 라우팅 결정과
충돌하지 않는다.

로컬 Dockerfile build가 생기므로 배포 script는 buildable service를 처리해야 한다.
현재 `docker compose pull`만으로는 local image가 갱신되지 않을 수 있다. 포털 추가 시
`docker compose up -d --build portal` 또는 전체 `docker compose up -d --build --wait`
전략을 결정한다.

## 검증

MVP 검증 기준:

1. `docker compose config`가 통과한다.
2. `portal` container가 Traefik `proxy` network에 연결된다.
3. `https://portal.kkh-hub.tech`가 Basic Auth를 요구한다.
4. 인증 후 Services 화면이 보인다.
5. Traefik dashboard와 Health/whoami 링크가 표시된다.
6. Skills 화면에서 skill list가 보인다.
7. frontmatter metadata와 rendered markdown이 분리되어 보인다.
8. `Copy original`, `Copy body`, `Copy install command`가 동작한다.
9. server health, DB/Redis status, API usage UI가 존재하지 않는다.

## 나중 단계

- Services 항목을 `compose.yml` 또는 OKF에서 생성.
- Status 화면 추가.
- API 사용량 요약.
- 외부 service health check.
- skill sync script 추가.
- favorites/tag filter 추가.
- SSO 전환.

