---
type: Service
title: ERD 서빙 (Liam ERD)
description: 프로젝트 DB 스키마의 ER 다이어그램을 erd 서브도메인에서 정적 파일로 제공한다.
tags: [erd, liam, nginx, static, basic-auth]
timestamp: 2026-09-30T00:00:00+09:00
---

# 개요

`erd.kkh-hub.tech/<프로젝트>/`는 각 프로젝트의 Liam ERD 산출물을 보여준다. 서버 프로세스가 없고, nginx가
`vps_erd_site` volume(컨테이너 안 `/var/www/erd`, read-only)의 파일을 직접 응답한다.
결정과 이유는 [ADR 0013](/adr/0013-liam-erd-static-hosting.md)에 있다.

# 소유 경계

| 위치 | 소유 |
|------|------|
| vps-infra 레포 | `nginx/templates/erd.conf.template`, `compose.yml`의 `erd-site` volume, `CHALLENGE_DOMAINS`의 `erd` |
| 각 프로젝트 레포 | Jenkinsfile의 ERD stage (빌드하고 volume의 `/<프로젝트>/`를 채운다) |
| VPS 1회 작업 | `erd` DNS A 레코드 |

# 접근

공용 Basic Auth(`secrets/basic-auth.htpasswd.sops.txt`)를 쓴다. 계정은 `scripts/set-basic-auth.sh`로 바꾼다.

# 프로젝트 추가

1. 프로젝트 Jenkinsfile에 ERD stage를 넣는다. 입력은 스키마 파일이다(Drizzle은 `schema.ts`, 그 밖은 `pg_dump -s`).
2. `docker run -v vps_erd_site:/out`으로 `/out/<프로젝트>/`에 복사한다.
3. nginx 설정은 바꾸지 않는다. 폴더가 생기면 바로 서빙된다.

# 관련 개념

- [nginx 리버스 프록시](/services/nginx.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
