---
type: Deployment Service
title: Jenkins 배포
description: VPS 내부 Docker Jenkins가 GitHub webhook을 받아 인프라를 배포한다.
tags: [deployment, jenkins, docker, webhook]
timestamp: 2026-07-20T00:00:00+09:00
---

# 개요

Jenkins는 기존 인프라 Compose project와 분리된 Docker Compose project로
실행한다. Traefik 뒤 `jenkins.kkh-hub.tech`로 접근하며, GitHub webhook이
Pipeline을 시작한다.

이번 단계에서는 GHCR를 사용하지 않는다. Jenkins가 `/opt/vps-infra`에서
repository를 checkout하고, VPS Docker daemon에서 portal 이미지를 build한 뒤
기존 `scripts/deploy.sh`를 실행한다.

# 흐름

```txt
GitHub push
-> GitHub webhook
-> Jenkins container
-> /opt/vps-infra checkout
-> docker compose config
-> scripts/deploy.sh
-> scripts/healthcheck.sh
```

Jenkins가 Docker socket을 사용하므로 host Docker daemon에 높은 권한을 가진다.
Jenkins 관리자와 Pipeline 수정 권한을 제한하고, public 접근은 Traefik HTTPS와
Jenkins 인증 뒤에 둔다.

# 초기화

Jenkins 설치는 관리자 SSH 또는 VPS console에서 1회 수행한다.

```bash
cd /opt/vps-infra/jenkins
mkdir -p /opt/jenkins
cp .env.example /opt/jenkins/.env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" /opt/jenkins/.env
docker compose --env-file /opt/jenkins/.env up -d --build
```

이후 배포마다 수동 SSH 또는 VPS 내부 `git clone`은 필요하지 않다. Jenkins가
checkout과 Docker 명령을 수행한다.

# 보안

- Jenkins를 기존 `compose.yml`에 넣지 않는다. 배포 중 Jenkins 재생성을 피한다.
- `8080`을 public port로 publish하지 않는다. Traefik만 `80/443`을 노출한다.
- Jenkins GitHub credential과 administrator password를 repository에 저장하지 않는다.
- Jenkins의 anonymous read와 signup을 비활성화한다.
- `/var/run/docker.sock` mount는 host Docker 제어 권한을 의미한다.

# 관련 개념

- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
