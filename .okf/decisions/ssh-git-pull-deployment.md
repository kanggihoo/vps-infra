---
type: Decision
title: SSH Git-Pull 배포
description: GitHub Actions가 SSH로 VPS에 접속하고 VPS에서 git pull을 실행한다.
tags: [deployment, github-actions, ssh]
timestamp: 2026-06-28T00:00:00+09:00
---

# 결정

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

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
