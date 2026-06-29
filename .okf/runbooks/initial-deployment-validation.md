---
type: Runbook
title: 초기 배포 검증
description: 첫 인프라 배포 성공 기준.
tags: [validation, deployment, operations]
timestamp: 2026-06-29T00:00:00+09:00
---

# 실행 시점

첫 `main` push 배포 후, VPS 재부팅 테스트 후, 또는 DNS/firewall/Traefik/PostgreSQL/Redis
설정을 바꾼 뒤 실행한다.

# 성공 기준

1. GitHub Actions가 `main` push에서 성공한다.
2. `/home/kkh/vps-infra`가 최신 `main`으로 갱신된다.
3. `docker compose config`가 통과한다.
4. [Traefik](/services/traefik.md), [PostgreSQL](/services/postgresql.md),
   [Redis](/services/redis.md), [whoami](/services/whoami.md)가 running 상태다.
5. `https://health.kkh-hub.tech`가 whoami 응답을 반환한다.
6. `https://traefik.kkh-hub.tech`가 Basic Auth를 요구하고 dashboard를 보여준다.
7. PostgreSQL `pg_isready`가 통과한다.
8. Redis가 `PONG`을 반환한다.
9. 외부에서 접근 가능한 public port는 `80`, `443`뿐이다.

# 관련 개념

- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [장애 진단](/runbooks/failure-diagnosis.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
