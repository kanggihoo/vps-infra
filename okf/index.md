---
okf_version: "0.1"
---

# VPS 인프라 지식 번들

Hostinger VPS 인프라 프로젝트의 핵심 지식을 담는 OKF 번들.

# 그룹

* [서비스](services/) - VPS 인프라가 운영하는 런타임 구성요소.
* [아키텍처](architecture/) - 전체 배포/런타임/네트워크 구조.
* [결정 (ADR)](adr/) - 아키텍처와 운영 결정 기록.
* [스펙](spec/) - 구현 전 합의된 변경 계획.
* [런북](runbooks/) - 배포 검증과 장애 진단 절차.
* [환경](environments/) - 배포 대상 VPS와 public 운영 메타데이터.

# 핵심 개념

* [로컬 우선 인프라 재구성](spec/0001-local-first-infra.md) - 진행 예정인 대규모 변경의 범위와 작업 순서.
* [Jenkins가 VPS에서 이미지를 빌드한다](adr/0006-jenkins-builds-on-vps.md) - 빌드를 외부 CI로 넘기지 않는 근거와 리소스 실측.
* [프로젝트별 독립 Compose](adr/0007-per-project-compose.md) - 각 프로젝트가 자기 레포에서 compose와 이미지를 소유한다.
* [nginx 설정의 환경 템플릿화](adr/0008-nginx-env-templates.md) - envsubst 템플릿 한 벌로 로컬과 VPS를 커버한다.
* [Jenkins 설정을 코드로 관리](adr/0009-jenkins-config-as-code.md) - JCasC와 job-dsl로 설정과 Job을 레포에서 관리한다.
* [SOPS 기반 secret 관리](adr/0010-sops-secrets.md) - secret을 암호화해 레포에 커밋하고 복호화 key만 각 환경에 둔다.
* [GitHub Actions 배포](services/github-actions-deploy.md) - 폐기된 배포 경로. 현재는 검증 전용으로 전환한다.
* [Jenkins 배포](services/jenkins-deploy.md) - VPS 내부 Jenkins가 GitHub webhook을 받아 Docker Compose 배포를 실행한다.
* [nginx 리버스 프록시](services/nginx.md) - VPS의 public HTTP/HTTPS 진입점.
* [공용 인프라 포털](services/portal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
* [Frontend Design Skills](services/frontend-design-skills.md) - 포털과 frontend 작업을 위해 project scope로 설치된 Codex frontend design skill set.
* [시스템 아키텍처 개요](architecture/system-overview.md) - Hostinger VPS 1대에서 Jenkins, nginx, Docker Compose, PostgreSQL, Redis가 연결되는 전체 구조.
* [공용 인프라 포털 MVP 아키텍처](architecture/portal-dashboard-proposal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털 MVP 구조.
* [Hostinger VPS](environments/hostinger-vps.md) - 현재 인프라가 배포될 VPS와 public 운영 메타데이터.
* [초기 배포 검증](runbooks/initial-deployment-validation.md) - 첫 인프라 배포 성공 기준.
