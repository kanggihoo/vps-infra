---
type: Decision
title: Jenkins 내부 배포
description: VPS 내부 Docker Jenkins가 webhook으로 배포를 실행한다.
tags: [deployment, jenkins, docker, webhook]
timestamp: 2026-07-20T00:00:00+09:00
---

# 상태

Jenkins를 별도 Compose project로 두고 webhook으로 배포하는 골격은 유효하다.
다음 항목은 이후 결정으로 대체되었다.

- 배포 경로가 `/opt/vps-infra`에서 홈 디렉터리 아래 `app/`으로 바뀐다. root 소유
  경로가 권한 문제를 일으켰기 때문이다.
- Jenkins 설정과 Job은 [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)로
  레포에서 관리한다.
- 각 프로젝트 배포는 [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)를 따른다.
- Jenkins가 이미지 빌드까지 수행하는 근거는
  [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md)에 있다.

# 결정

VPS에 Jenkins를 별도 Docker Compose project로 설치한다. Jenkins는 GitHub
webhook을 받아 repository를 checkout하고, VPS Docker daemon에서 배포 script를
실행한다.

# 이유

- 현재 VPS에서 Docker build와 Compose 실행이 가능하다.
- 배포마다 GitHub Actions가 VPS에 SSH 접속하는 구조를 제거한다.
- GHCR 없이 현재 `portal` local build 구조를 재사용할 수 있다.
- Jenkins와 인프라 stack을 분리해 배포 중 Jenkins 재생성을 피한다.

# 결과

- Jenkins 설치와 초기 설정에는 관리자 SSH 또는 VPS console 1회가 필요하다.
- Jenkins container는 `/var/run/docker.sock`을 사용하므로 host Docker 제어 권한을 가진다.
- public Jenkins port는 열지 않고 nginx HTTPS 뒤에 둔다.
- GitHub Actions 자동 workflow는 중지하고 수동 emergency 경로로만 유지한다.
- Jenkins가 사용하는 GitHub checkout credential은 Jenkins 내부에만 저장한다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
