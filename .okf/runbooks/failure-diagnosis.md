---
type: Runbook
title: 장애 진단
description: DNS, firewall, Traefik, Compose, container 문제를 순서대로 진단하는 절차.
tags: [operations, troubleshooting, deployment]
timestamp: 2026-06-28T00:00:00+09:00
---

# 순서

초기 배포 검증이 실패하면 다음 순서로 확인한다.

```txt
DNS
-> Hostinger/VPS firewall
-> Traefik logs
-> docker compose ps
-> container logs
-> health checks
```

# 확인 항목

| 계층 | 확인 내용 |
|------|-----------|
| DNS | `traefik.kkh-hub.tech`, `health.kkh-hub.tech`가 `187.77.114.68`로 resolve되는지 확인한다. |
| Firewall | Hostinger와 VPS가 inbound `80`, `443`을 허용하는지 확인한다. |
| Traefik | [Traefik](/services/traefik.md)이 시작되고, `80/443`을 소유하며, 인증서를 발급하는지 확인한다. |
| Compose | 기대한 컨테이너가 running 상태인지 확인한다. |
| Container logs | backend service error, PostgreSQL readiness, Redis auth/readiness를 확인한다. |
| Health checks | [초기 배포 검증](/runbooks/initial-deployment-validation.md)이 통과하는지 확인한다. |

# 관련 개념

- [Traefik 리버스 프록시](/services/traefik.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
