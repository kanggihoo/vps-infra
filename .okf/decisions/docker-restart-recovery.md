---
type: Decision
title: Docker 재시작 복구
description: Docker daemon boot enablement와 restart unless-stopped를 사용한다.
tags: [docker, reboot, operations]
timestamp: 2026-06-28T00:00:00+09:00
---

# 결정

VPS 재부팅 복구는 Docker daemon 자동 시작과 Compose restart policy로 처리한다.

# 방식

Docker를 boot 시 자동 시작하도록 설정한다.

```bash
sudo systemctl enable docker
```

Compose service에는 다음을 설정한다.

```yaml
restart: unless-stopped
```

# 이유

`docker compose up -d`로 컨테이너가 한 번 생성되면 Docker는 저장된 컨테이너
metadata와 restart policy를 보고 재부팅 후 컨테이너를 다시 시작할 수 있다.
1차 단계에서는 Compose project용 별도 systemd unit이 필요하지 않다.

# 관련 개념

- [Traefik 리버스 프록시](/services/traefik.md)
- [PostgreSQL](/services/postgresql.md)
- [Redis](/services/redis.md)
- [whoami Health Target](/services/whoami.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
