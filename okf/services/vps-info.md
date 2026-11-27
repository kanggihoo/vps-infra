---
type: Service
title: vps-info (Signal Archive)
description: 자기 레포에서 compose와 GitHub Actions CI/CD를 소유하고 공용 PostgreSQL과 nginx를 쓰는 첫 외부 프로젝트.
tags: [project, github-actions, ghcr, sops, postgres, nginx]
timestamp: 2026-11-27T00:00:00+09:00
---

# 개요

`kanggihoo/vps-info`(Signal Archive)는 [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)를
처음 적용한 외부 프로젝트다. `info.kkh-hub.tech`로 노출되며 nginx의 Tinyauth SSO 뒤에 있다([ADR 0022](/adr/0022-tinyauth-sso.md)).

# 소유 경계

| 위치 | 소유 |
|------|------|
| vps-info 레포 | `Dockerfile`, `compose.yml`(프로젝트 이름 `vps-info`), `.github/workflows/ci.yml`, `scripts/deploy.sh`, `scripts/erd.sh`, `secrets/env.prod.sops.env` |
| GitHub 설정 | main branch protection의 필수 check `check:task`, 레포 secret `VPS_DEPLOY_KEY`·`MATTERMOST_WEBHOOK_URL`, GHCR 패키지 `ghcr.io/kanggihoo/vps-info`(public) |
| vps-infra 레포 | `nginx/templates/vps-info.conf.template`, `CHALLENGE_DOMAINS` |
| VPS 1회 작업 | 공용 postgres의 `vps_info` 사용자·DB (superuser를 공유하지 않는다), `~/app/vps-info` clone, `authorized_keys`의 `vps-info-deploy` forced command 줄 |

# 배포 흐름

```txt
PR -> GitHub Actions CI (check:task) -> 병합 필수 check, Mattermost CI 알림 (ADR 0018)
vps-info main push -> GitHub Actions (ADR 0019)
-> check:task -> image: ghcr.io/kanggihoo/vps-info:<sha>-<서비스> push
-> deploy: ssh kkh@VPS "<sha>" -> forced command ~/app/vps-info/scripts/deploy.sh
   -> flock /tmp/vps-deploy.lock -> git checkout <sha>(main 이력만)
   -> sops 이미지 + ~/.config/sops/age/keys.txt로 .env 복호화(+ IMAGE_TAG)
   -> docker compose pull -> up -d --no-build --wait (migrate 성공 후 app, collector, llm)
   -> 마이그레이션이 바뀌었으면 scripts/erd.sh
-> notify: Mattermost CD 알림
```

- nginx는 서비스 이름 `app` 대신 `vps_proxy` alias `vps-info-app`으로 찾는다. 공유 네트워크에서
  서비스 이름이 겹치면 Docker DNS가 요청을 나눠 보낸다.
- DB 접속 호스트는 `vps-postgres`(container_name)다. 같은 이유로 서비스 이름 `postgres`를 쓰지 않는다.
- 암호화는 vps-infra와 같은 age 공개키를 쓴다. VPS의 `~/.config/sops/age/keys.txt` 하나로 복호화된다.

# 주의

- 배포 key는 `command="/home/kkh/app/vps-info/scripts/deploy.sh",restrict`로 묶여 셸·다른 명령·포트 포워딩이 안 된다(2026-11-20 확인).
  key를 바꿀 때는 `authorized_keys`의 `vps-info-deploy` 줄과 레포 secret `VPS_DEPLOY_KEY`를 함께 바꾼다.
- workflow는 VPS host key를 고정한다(`ci.yml`의 `VPS_HOST_KEY`). VPS를 다시 만들면 그 값도 바꿔야 배포된다.
- 롤백은 VPS에서 `~/app/vps-info/scripts/deploy.sh <이전 main SHA>`다. 수동 재배포·ERD 재생성은 Actions `CI` workflow를 main으로 실행한다(`erd` 옵션).
- 운영 compose 명령(`scripts/llm-login.sh` 등)은 `~/app/vps-info`에서 실행한다. `.env`의 `IMAGE_TAG`가 배포된 이미지를 가리킨다.
- macOS의 sops는 age key를 `~/Library/Application Support/sops/age/keys.txt`에서 찾는다.
  key가 `~/.config/sops/age/keys.txt`에 있으면 `SOPS_AGE_KEY_FILE`로 지정한다.

# 관련 개념

- [vps-info 배포를 GitHub Actions로 옮긴다](/adr/0019-vps-info-cd-on-github-actions.md)
- [nginx 리버스 프록시](/services/nginx.md)
- [PostgreSQL](/services/postgresql.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
