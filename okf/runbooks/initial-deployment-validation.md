---
type: Runbook
title: 초기 배포 검증
description: 첫 인프라 배포 성공 기준.
tags: [validation, deployment, operations]
timestamp: 2026-09-13T00:00:00+09:00
---

# 실행 시점

첫 `main` push 배포 후, VPS 재부팅 테스트 후, 또는 DNS/firewall/nginx/PostgreSQL/Redis
설정을 바꾼 뒤 실행한다.

# 성공 기준

1. Jenkins가 GitHub webhook으로 시작되어 성공한다.
2. `~/app/vps-infra`가 최신 `main`으로 갱신된다.
3. `docker compose config`가 통과한다.
4. [nginx](/services/nginx.md), [PostgreSQL](/services/postgresql.md),
   [Redis](/services/redis.md), [whoami](/services/whoami.md), portal이
   running 상태다.
5. `https://health.kkh-hub.tech`가 whoami 응답을 반환한다.
6. `https://portal.kkh-hub.tech`, `https://jenkins.kkh-hub.tech`가 유효한 TLS
   인증서로 응답한다.
7. PostgreSQL `pg_isready`가 통과한다.
8. Redis가 `PONG`을 반환한다.
9. 외부에서 접근 가능한 public port는 `80`, `443`뿐이다.
10. `systemctl status vps-infra-certbot-renew.timer`가 enabled·active이고,
    `systemctl list-timers vps-infra-certbot-renew.timer`에 다음 실행 시각이 나온다.

# 인증서 갱신 timer 설치

VPS에서 다음을 한 번 실행한다. `/etc/vps-infra/certbot-renew.env`는 checkout 절대 경로만
담으므로 root 소유 `0644` 권한으로 둔다.

```bash
cd ~/app/vps-infra
sudo install -d -m 755 /etc/vps-infra
sudo install -m 644 systemd/certbot-renew.env.example /etc/vps-infra/certbot-renew.env
sudoedit /etc/vps-infra/certbot-renew.env
sudo install -m 644 systemd/vps-infra-certbot-renew.service /etc/systemd/system/
sudo install -m 644 systemd/vps-infra-certbot-renew.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vps-infra-certbot-renew.timer
sudo systemctl start vps-infra-certbot-renew.service
```

실행 결과는 `journalctl -u vps-infra-certbot-renew.service`에서 확인한다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [장애 진단](/runbooks/failure-diagnosis.md)
