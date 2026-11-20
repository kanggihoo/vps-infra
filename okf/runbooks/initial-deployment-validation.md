---
type: Runbook
title: 초기 배포 검증
description: 첫 인프라 배포 성공 기준.
tags: [validation, deployment, operations]
timestamp: 2026-11-20T00:00:00+09:00
---

# 실행 시점

첫 `main` push 배포 후, VPS 재부팅 테스트 후, 또는 DNS/firewall/nginx/PostgreSQL/Redis
설정을 바꾼 뒤 실행한다.

# 성공 기준

1. GitHub Actions `Validate infra config`의 validate·deploy job이 성공한다.
2. `~/app/vps-infra`가 배포한 `main` SHA로 checkout되어 있다(`git log -1`).
3. `docker compose config`가 통과한다.
4. [nginx](/services/nginx.md), [PostgreSQL](/services/postgresql.md),
   [Redis](/services/redis.md), [whoami](/services/whoami.md), portal이
   running 상태다.
5. `https://health.kkh-hub.tech`가 whoami 응답을 반환한다.
6. `https://portal.kkh-hub.tech`, `https://grafana.kkh-hub.tech`가 유효한 TLS
   인증서로 응답한다.
7. PostgreSQL `pg_isready`가 통과한다.
8. Redis가 `PONG`을 반환한다.
9. 외부에서 접근 가능한 public port는 `80`, `443`뿐이다.
10. `vps-certbot` 컨테이너가 running이고 `docker logs vps-certbot`에 renew 결과가 남는다.

# 관련 개념

- [배포](/services/deploy.md)
- [장애 진단](/runbooks/failure-diagnosis.md)
