---
type: Service
title: Redis
description: 향후 서비스 캐시/세션 용도로 쓸 공통 Redis 컨테이너.
tags: [redis, cache, acl, docker]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

Redis는 VPS 인프라 안에서 공통 컨테이너 1개로 실행한다. 외부에는 노출하지 않는다.
1차 단계에서는 접근 보호를 설정하고 `PING`으로 liveness만 검증한다.

# 초기 단계

- Redis 컨테이너 1개.
- host port `6379` 미노출.
- password 또는 ACL admin 설정으로 보호.
- `redis-cli ping`으로 health check.

# 향후 앱 격리

향후 서비스별로 ACL user와 key prefix를 부여한다.

```txt
app1_user -> ~app1:* access
app2_user -> ~app2:* access
```

Redis logical DB number는 격리 경계로 사용하지 않는다.

# 제한할 명령

앱 수준 사용자는 다음 위험 명령 권한을 받지 않는다.

```txt
FLUSHALL
FLUSHDB
CONFIG
KEYS
EVAL
SCRIPT
```

# 관계

이 서비스는 [공통 데이터 서비스 결정](/decisions/shared-data-services.md)을 따른다.
[초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 상태를 확인한다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
