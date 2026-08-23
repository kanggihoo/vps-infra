---
type: Decision
title: SSH Git-Pull 배포
description: Jenkins 전환 전 GitHub Actions가 SSH로 VPS에 접속하고 VPS에서 git pull을 실행하던 방식.
tags: [deployment, github-actions, ssh]
timestamp: 2026-06-28T00:00:00+09:00
---

# 상태

**폐기.** Jenkins migration 후 수동 rollback 경로로만 남아 있었으나, 그마저 제거한다.

배포 경로를 이중으로 유지하면 양쪽이 함께 낡는다. 실제로 `.github/workflows/deploy.yml`은
`workflow_dispatch`에서 `github.event.before`를 참조하는데 그 값이 비어 있어 항상
`target=all`로 떨어지는 상태였다.

GitHub Actions는 배포에서 빼고 **검증 전용**으로 전환한다(`docker compose config`,
`nginx -t`, SOPS 파일 무결성). Jenkins 장애 시 비상 수단은 SSH 접속 후 직접
`docker compose up`이며, 이는 문서로 관리한다.

현재 자동 배포 경로는 [Jenkins 내부 배포](/adr/0004-jenkins-deployment.md)다.

# 과거 결정

GitHub Actions에서 Hostinger VPS에 SSH로 접속한 뒤 `/opt/vps-infra`에서
`git pull`과 Docker Compose 명령을 실행한다.

# 이유

- 기존 운영 경험이 GitHub Actions + SSH 방식과 맞다.
- VPS 안에서 `git status`, `git log`, `git diff`로 상태 확인이 쉽다.
- 인프라 repository는 텍스트 파일 중심이라 VPS clone 용량 부담이 작다.
- 이 프로젝트의 런타임 경계는 Docker Compose다.

# 결과

- VPS에 `/opt/vps-infra` repository clone이 필요하다.
- GitHub Actions 전용 배포 SSH key가 필요하다.
- 런타임 secret은 VPS의 `.env`에 둔다.

# 관련 개념

- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
