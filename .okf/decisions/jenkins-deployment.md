---
type: Decision
title: Jenkins 내부 배포
description: VPS 내부 Docker Jenkins가 webhook으로 배포를 실행한다.
tags: [deployment, jenkins, docker, webhook]
timestamp: 2026-07-20T00:00:00+09:00
---

# 결정

VPS에 Jenkins를 별도 Docker Compose project로 설치한다. Jenkins는 GitHub
webhook을 받아 `/opt/vps-infra`를 checkout하고, VPS Docker daemon에서
`scripts/deploy.sh`와 `scripts/healthcheck.sh`를 실행한다.

# 이유

- 현재 VPS에서 Docker build와 Compose 실행이 가능하다.
- 배포마다 GitHub Actions가 VPS에 SSH 접속하는 구조를 제거한다.
- GHCR 없이 현재 `portal` local build 구조를 재사용할 수 있다.
- Jenkins와 인프라 stack을 분리해 배포 중 Jenkins 재생성을 피한다.

# 결과

- Jenkins 설치와 초기 설정에는 관리자 SSH 또는 VPS console 1회가 필요하다.
- Jenkins container는 `/var/run/docker.sock`을 사용하므로 host Docker 제어 권한을 가진다.
- public Jenkins port는 열지 않고 Traefik HTTPS 뒤에 둔다.
- GitHub Actions 자동 workflow는 중지하고 수동 emergency 경로로만 유지한다.
- Jenkins가 사용하는 GitHub checkout credential은 Jenkins 내부에만 저장한다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
