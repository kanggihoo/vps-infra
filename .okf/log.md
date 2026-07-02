# 변경 기록

## 2026-07-03
* **갱신**: [공용 인프라 포털](/services/portal.md)의 Basic Auth middleware를 제거하고, 현재 MVP는 공개 가능한 링크와 skill 원문만 제공한다고 기록했다.
* **갱신**: [GitHub Actions 배포](/services/github-actions-deploy.md)에 `portal/**` 변경만 있을 때 포털 service만 rebuild/recreate하는 target 배포 흐름을 추가했다.
* **생성**: [공용 인프라 포털](/services/portal.md) service concept를 추가했다.
* **갱신**: [공용 인프라 포털 MVP 아키텍처](/architecture/portal-dashboard-proposal.md)를 Services와 Skills 중심의 React+Go 단일 포털 구조로 정리하고, 운영 관측 기능을 MVP 범위에서 제외했다.

## 2026-07-01
* **생성**: React+nginx 포털 UI와 Go net/http 기반 경량 상태 API를 사용하는 [서비스 포털 대시보드 후보 아키텍처](/architecture/portal-dashboard-proposal.md)를 추가했다.

## 2026-06-29
* **갱신**: 앞으로 할 일 문서에 CI/CD 실패 텔레그램 알림, Traefik SSO 연동, 브랜치 보호 작업 후보를 추가했다.
* **생성**: 앞으로 진행할 작업 후보를 기록하는 로드맵 concept를 추가했다.
* **갱신**: [시스템 아키텍처 개요](/architecture/system-overview.md)에 구현된 Docker network 이름 `vps_proxy`, `vps_data`를 명시했다.

## 2026-06-28
* **생성**: 전체 배포/런타임/네트워크 구조를 담는 [시스템 아키텍처 개요](/architecture/system-overview.md)를 추가했다.
* **생성**: AI 작업 진입점인 repository root `AGENTS.md`를 추가했다.
* **생성**: public 운영 메타데이터를 담는 [Hostinger VPS](/environments/hostinger-vps.md) 환경 개념을 추가했다.
* **생성**: VPS 인프라 설계 지식을 OKF 번들로 정리했다.
* **생성**: [GitHub Actions 배포](/services/github-actions-deploy.md), [Traefik 리버스 프록시](/services/traefik.md), [PostgreSQL](/services/postgresql.md), [Redis](/services/redis.md), [whoami Health Target](/services/whoami.md) 서비스 개념을 추가했다.
* **생성**: 배포 방식, 라우팅 방식, 데이터 서비스 격리, 재부팅 복구 결정을 추가했다.
* **생성**: [초기 배포 검증](/runbooks/initial-deployment-validation.md), [장애 진단](/runbooks/failure-diagnosis.md) 런북을 추가했다.
* **생성**: 원본 설계 문서를 가리키는 [VPS 인프라 GitHub Actions 배포 설계](/references/vps-infra-github-actions-design.md) reference concept를 추가했다.
