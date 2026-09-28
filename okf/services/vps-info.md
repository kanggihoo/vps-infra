---
type: Service
title: vps-info (Signal Archive)
description: 자기 레포에서 compose와 Jenkinsfile을 소유하고 공용 PostgreSQL과 nginx를 쓰는 첫 외부 프로젝트.
tags: [project, jenkins, sops, postgres, nginx]
timestamp: 2026-09-28T00:00:00+09:00
---

# 개요

`kanggihoo/vps-info`(Signal Archive)는 [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)를
처음 적용한 외부 프로젝트다. `info.kkh-hub.tech`로 노출되며 notes와 같은 Basic Auth(`secrets/notes.htpasswd.sops.txt`)를 쓴다.

# 소유 경계

| 위치 | 소유 |
|------|------|
| vps-info 레포 | `Dockerfile`, `compose.yml`(프로젝트 이름 `vps-info`), `Jenkinsfile`, `secrets/env.prod.sops.env` |
| vps-infra 레포 | `jenkins/jobs.groovy`의 `vps-info` Job, `nginx/templates/vps-info.conf.template`, `CHALLENGE_DOMAINS` |
| VPS 1회 작업 | 공용 postgres의 `vps_info` 사용자·DB (superuser를 공유하지 않는다) |

# 배포 흐름

```txt
vps-info main push -> GitHub webhook -> Jenkins vps-info Job
-> docker build --target test (단위 테스트)
-> sops-age-key credential로 secrets/env.prod.sops.env 복호화 -> .env
-> docker compose up -d --build --wait (migrate 성공 후 app, collector)
-> post: .env 삭제
```

- nginx는 서비스 이름 `app` 대신 `vps_proxy` alias `vps-info-app`으로 찾는다. 공유 네트워크에서
  서비스 이름이 겹치면 Docker DNS가 요청을 나눠 보낸다.
- DB 접속 호스트는 `vps-postgres`(container_name)다. 같은 이유로 서비스 이름 `postgres`를 쓰지 않는다.
- 암호화는 vps-infra와 같은 age 공개키를 쓴다. 새 프로젝트도 같은 key로 복호화되므로
  Jenkins credential을 추가하지 않는다.

# 주의

- Jenkins 설정은 이미지에 복사되므로 `jobs.groovy`에 Job을 추가하면 Jenkins 재빌드가 필요하다
  ([ADR 0009](/adr/0009-jenkins-config-as-code.md)). 2026-09-28 적용 때는 재빌드 후 Job의
  `config.xml`만 생기고 목록에 나타나지 않아 한 번 더 재시작해야 했다.
- macOS의 sops는 age key를 `~/Library/Application Support/sops/age/keys.txt`에서 찾는다.
  key가 `~/.config/sops/age/keys.txt`에 있으면 `SOPS_AGE_KEY_FILE`로 지정한다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [nginx 리버스 프록시](/services/nginx.md)
- [PostgreSQL](/services/postgresql.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
