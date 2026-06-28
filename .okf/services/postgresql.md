---
type: Service
title: PostgreSQL
description: 향후 서비스별 DB를 담을 공통 PostgreSQL 컨테이너.
tags: [postgresql, database, docker, persistence]
timestamp: 2026-06-28T00:00:00+09:00
---

# 개요

PostgreSQL은 VPS 인프라 안에서 공통 컨테이너 1개로 실행한다. 외부에는 노출하지
않는다. 1차 단계에서는 Docker 환경변수로 admin/superuser와 기본 DB만 생성한다.

# 초기 단계

- PostgreSQL 컨테이너 1개.
- Docker volume으로 데이터 영속화.
- host port `5432` 미노출.
- admin/superuser와 기본 DB만 생성.
- `pg_isready`로 health check.

# 향후 앱 격리

향후 서비스별로 database와 role을 분리한다.

```txt
app1_db + app1_user
app2_db + app2_user
authentik_db + authentik_user
```

각 서비스 사용자는 자기 DB에만 접근한다. 앱은 PostgreSQL superuser를 사용하지 않는다.

# 거부한 격리 방식

테이블 prefix만으로 분리하는 방식은 보안 경계로 보지 않는다.

# 관계

이 서비스는 [공통 데이터 서비스 결정](/decisions/shared-data-services.md)을 따른다.
[초기 배포 검증](/runbooks/initial-deployment-validation.md)에서 상태를 확인한다.

# Citations

[1] [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md)
