---
type: Service
title: ERD 서빙 (Liam ERD)
description: 프로젝트 DB 스키마의 ER 다이어그램을 erd 서브도메인에서 정적 파일로 제공한다.
tags: [erd, liam, nginx, static, tinyauth]
timestamp: 2026-11-27T00:00:00+09:00
---

# 개요

`erd.kkh-hub.tech/<프로젝트>/`는 각 프로젝트의 Liam ERD 산출물을 보여준다. 서버 프로세스가 없고, nginx가
`vps_erd_site` volume(컨테이너 안 `/var/www/erd`, read-only)의 파일을 직접 응답한다.
결정과 이유는 [ADR 0013](../../docs/adr/0013-liam-erd-static-hosting.md)에 있다.

# 소유 경계

| 위치 | 소유 |
|------|------|
| vps-infra 레포 | `nginx/templates/erd.conf.template`, `compose.yml`의 `erd-site` volume, `CHALLENGE_DOMAINS`의 `erd` |
| 각 프로젝트 레포 | 배포 때 ERD를 빌드해 volume의 `/<프로젝트>/`를 채우는 스크립트 (vps-info: `scripts/erd.sh`) |
| VPS 1회 작업 | `erd` DNS A 레코드 |

# 접근

Tinyauth SSO 뒤에 있다([ADR 0022](../../docs/adr/0022-tinyauth-sso.md)). 미인증 요청은 `auth.kkh-hub.tech` 로그인으로 302된다.
계정은 `secrets/env.prod.sops.env`의 `TINYAUTH_AUTH_USERS`(로컬 계정)와 `TINYAUTH_OAUTH_WHITELIST`(Google 허용 이메일)로 바꾼다.

# 프로젝트 추가

1. 프로젝트 배포 스크립트에 ERD 단계를 넣는다(vps-info `scripts/erd.sh` 참고). 입력은 스키마 파일이다(Drizzle은 `schema.ts`, 그 밖은 `pg_dump -s`).
2. `docker run -v vps_erd_site:/out`으로 `/out/<프로젝트>/`에 복사한다.
3. nginx 설정은 바꾸지 않는다. 폴더가 생기면 바로 서빙된다.

# 관련 개념

- [nginx 리버스 프록시](/services/nginx.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
