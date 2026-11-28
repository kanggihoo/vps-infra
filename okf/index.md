---
okf_version: "0.1"
---

# VPS 인프라 지식 번들

Hostinger VPS 인프라 프로젝트의 핵심 지식을 담는 OKF 번들.

# 그룹

* [서비스](services/) - VPS 인프라가 운영하는 런타임 구성요소.
* [아키텍처](architecture/) - 전체 배포/런타임/네트워크 구조.
* [결정 (ADR)](../docs/adr/index.md) - 아키텍처와 운영 결정 기록.
* [런북](runbooks/) - 배포 검증과 장애 진단 절차.
* [트러블슈팅](troubleshooting/) - 운영 중 겪은 문제의 증상, 조사, 원인, 조치 사례.
* [환경](environments/) - 배포 대상 VPS와 public 운영 메타데이터.
* [도구](tooling/) - 프로젝트 개발과 운영을 지원하는 도구 및 skill.

# 핵심 개념

* [Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md) - 2026-09-11 저장소 정적 리뷰와 운영 확인 항목, 개선 우선순위.
* [A302 인프라 도입 후보 검토](/architecture/a302-adoption-candidates.md) - 종료된 A302의 운영 결과를 반영한 미확정 후보 26개와 우선순위(인증서·컨테이너 알림, 보안 헤더, 디스크, R2 백업, 재구축 표, 검증 후 배포·롤백 등 CI/CD).

* [PR 생성 webhook이 유실되어 PR이 Jenkins에 나타나지 않는다](troubleshooting/webhook-pr-event-lost.md) - 연결 단계 실패로 PR #3만 누락된 사례의 조사 과정과 진단 순서.
* [관측 스택](services/observability.md) - Grafana·Prometheus·Loki·Tempo·Alloy로 메트릭·로그·트레이스를 모은다.
* [ERD 서빙 (Liam ERD)](services/erd.md) - 프로젝트 DB 스키마의 ER 다이어그램을 erd 서브도메인에서 정적 파일로 제공한다.
* [과거 GitHub Actions SSH 배포](services/github-actions-deploy.md) - 폐기된 SSH 배포 경로 기록. 현재 배포는 services/deploy.md에 있다.
* [배포](services/deploy.md) - 각 레포의 GitHub Actions가 SSH forced command로 배포한다. vps-infra는 CI gate 뒤 Portal 이미지를 게시하고 VPS에서 digest로 적용할 수 있다.
* [vps-info (Signal Archive)](services/vps-info.md) - 자기 레포에서 compose와 GitHub Actions CI/CD를 소유하는 첫 외부 프로젝트.
* [nginx 리버스 프록시](services/nginx.md) - VPS의 public HTTP/HTTPS 진입점.
* [공용 인프라 포털](services/portal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
* [Frontend Design Skills](tooling/frontend-design-skills.md) - 포털과 frontend 작업을 위해 project scope로 설치된 Codex frontend design skill set.
* [시스템 아키텍처 개요](architecture/system-overview.md) - Hostinger VPS 1대에서 nginx, Docker Compose, PostgreSQL, Redis가 연결되고 GitHub Actions가 배포하는 전체 구조.
* [공용 인프라 포털 MVP 아키텍처](architecture/portal-dashboard-proposal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털 MVP 구조.
* [Hostinger VPS](environments/hostinger-vps.md) - 현재 인프라가 배포될 VPS와 public 운영 메타데이터.
* [초기 배포 검증](runbooks/initial-deployment-validation.md) - 첫 인프라 배포 성공 기준.
* [로컬 우선 인프라 인수 절차](runbooks/local-first-handover.md) - spec 0001 단계 0~5 구현 후 사용자 작업과 로컬 검증 명령.
