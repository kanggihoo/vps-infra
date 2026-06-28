---
type: Decision
title: 공통 데이터 서비스
description: PostgreSQL 컨테이너 1개와 Redis 컨테이너 1개를 운영하고, 향후 서비스별 논리 격리를 적용한다.
tags: [postgresql, redis, isolation, docker]
timestamp: 2026-06-28T00:00:00+09:00
---

# 결정

인프라 Compose project 안에서 PostgreSQL 컨테이너 1개와 Redis 컨테이너 1개를
공통으로 운영한다.

# PostgreSQL 격리 모델

1차 단계에서는 기본 admin/superuser와 기본 DB만 만든다. 향후 서비스가 생기면
서비스별 database와 user를 생성한다.

```txt
app1_db + app1_user
app2_db + app2_user
```

# Redis 격리 모델

1차 단계에서는 Redis 접근 보호와 liveness만 검증한다. 향후 서비스가 생기면
서비스별 ACL user와 key prefix 규칙을 부여한다.

```txt
app1_user -> ~app1:* access
app2_user -> ~app2:* access
```

Redis logical DB index는 격리 경계로 보지 않는다.

# 이유

VPS 메모리와 운영 부담을 낮추면서, 나중에 서비스별 접근 분리를 적용할 수 있다.

# 관련 개념

- [PostgreSQL](/services/postgresql.md)
- [Redis](/services/redis.md)

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
