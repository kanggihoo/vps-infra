---
type: Environment
title: Hostinger VPS
description: 현재 인프라가 배포될 VPS와 public 운영 메타데이터.
tags: [hostinger, vps, environment, deployment]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

이 환경은 `vps-infra` repository가 관리하는 Hostinger VPS다. 민감 정보는 기록하지
않고, 배포와 라우팅에 필요한 public 운영 메타데이터만 보관한다.

# Public Metadata

| 항목 | 값 |
|------|----|
| Provider | Hostinger VPS |
| Public IP | `187.77.114.68` |
| Domain | `kkh-hub.tech` |
| SSH user | `kkh` |
| Deploy path | `/opt/vps-infra` |
| Public ports | `80`, `443` |

# DNS Records

초기 목표 DNS record:

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      traefik    187.77.114.68
A      health     187.77.114.68
```

# SSH / Docker 조건

`kkh` 사용자는 Docker 명령을 실행할 수 있어야 한다.

```txt
groups: kkh sudo users docker
```

GitHub Actions는 기존 개인 SSH key가 아니라 배포 전용 SSH key를 사용한다.
private key는 GitHub Actions secret에만 저장한다.

# Secret 제외 규칙

다음 값은 이 OKF bundle이나 Git tracked 파일에 기록하지 않는다.

- SSH private key.
- `.env` 실제 값.
- DB password.
- Redis password.
- Traefik Basic Auth hash.
- Let's Encrypt `acme.json`.

# 관련 개념

- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [Traefik 리버스 프록시](/services/traefik.md)
- [서브도메인 라우팅](/decisions/subdomain-routing.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
