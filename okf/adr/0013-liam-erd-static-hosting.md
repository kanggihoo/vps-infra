---
type: Decision
title: DB 스키마 ERD를 Liam으로 빌드해 nginx에서 정적으로 서빙한다
description: 각 프로젝트의 Jenkins job이 Liam ERD를 빌드해 erd-site 볼륨에 넣고, nginx가 erd 서브도메인의 하위 경로로 Basic Auth 뒤에서 서빙한다.
tags: [erd, liam, nginx, jenkins, static]
timestamp: 2026-09-30T00:00:00+09:00
---

# 결정

프로젝트의 DB 스키마 ERD는 [Liam ERD](https://github.com/liam-hq/liam) CLI로 빌드한다. 빌드는 각 프로젝트의
Jenkinsfile이 하고, 산출물(`dist`)을 named volume `vps_erd_site`의 `/<프로젝트>/`에 복사한다.
nginx는 `erd.<BASE_DOMAIN>/<프로젝트>/`로 그 파일을 직접 서빙하고 공용 Basic Auth를 건다.

```txt
프로젝트 main push -> 프로젝트 Jenkins job
-> liam erd build --input <스키마> --format <형식> --output-dir dist
-> dist를 vps_erd_site:/<프로젝트>/ 에 교체 복사
-> nginx (erd.conf.template, root /var/www/erd) -> erd.<도메인>/<프로젝트>/
```

# 이유

- **스키마 파일만 입력이다.** Liam은 DB에 접속하지 않는다. Drizzle(`--format drizzle`)은 `schema.ts`를 직접 읽고,
  다른 프로젝트는 `pg_dump --schema-only` 결과를 `--format postgres`로 넘긴다. 마이그레이션이 바뀌면 스키마 파일도
  바뀌므로 빌드마다 ERD가 최신이 된다.
- **정적 파일이라 프로세스가 없다.** 산출물은 `index.html`, `assets/`, `schema.json`이다. nginx가 요청마다 디스크에서
  읽으므로 산출물이 바뀌어도 nginx reload가 필요 없다([notes 정적 서빙](/services/nginx.md)과 같은 방식).
- **하위 경로 한 도메인이다.** 프로젝트마다 서브도메인을 만들면 템플릿, `CHALLENGE_DOMAINS`, 인증서 expand가 반복된다.
  산출물이 상대 경로(`./assets`, `./schema.json`)를 써서 하위 경로에서도 동작한다.
- **Basic Auth를 건다.** ERD는 테이블·컬럼 구조를 그대로 보여준다. GitHub Pages는 private 공개에 Enterprise가 필요하다.
  [공용 Basic Auth](/adr/0010-sops-secrets.md)를 재사용해 새 secret이 없다.

# 결과

- `try_files $uri $uri/ =404`를 쓴다. `$uri/index.html`로 직접 서빙하면 `/vps-info`(슬래시 없음)가 redirect 없이 200이 되어
  `./assets`가 `/assets`로 풀려 화면이 깨진다. `$uri/`는 nginx가 `/vps-info/`로 301 redirect한다.
- 이름이 고정인 `index.html`, `schema.json`은 `Cache-Control: no-cache`, `assets/`는 파일명 해시로 기본 캐시를 쓴다.
- `/`에서는 배포된 프로젝트 폴더 목록이 `autoindex`로 보인다.
- 복사 도중 요청이 오면 파일이 섞여 보일 수 있다. Jenkinsfile은 임시 폴더에 복사한 뒤 교체한다.
- `scripts/test-routing.sh`가 401, index/schema 서빙, 슬래시 redirect, no-cache를 검증한다.
- `erd` 도메인은 `CHALLENGE_DOMAINS`에 넣어야 인증서에 들어가고, DNS A 레코드는 사용자가 만든다.

# 관련 개념

- [ERD 서빙](/services/erd.md)
- [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)
- [nginx 리버스 프록시](/services/nginx.md)
