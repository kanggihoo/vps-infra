---
type: Reference
title: VPS 인프라 GitHub Actions 배포 설계
description: OKF 번들의 기준이 된 원본 설계 문서.
resource: docs/superpowers/specs/2026-06-28-vps-infra-github-actions-design.md
tags: [design, source, github-actions, vps-infra]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

이 reference concept는 repository의 설계 문서
`docs/superpowers/specs/2026-06-28-vps-infra-github-actions-design.md`를
OKF bundle 안에서 참조하기 위한 내부 anchor다.

# 포함 내용

- Hostinger VPS 1대 기준 인프라 목표.
- GitHub Actions + SSH git-pull 배포 방식.
- Traefik reverse proxy와 TLS/DNS 기준.
- PostgreSQL, Redis 초기 운영 기준.
- 재부팅 복구, 검증, 장애 진단 기준.

# 관련 개념

- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [Traefik 리버스 프록시](/services/traefik.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
