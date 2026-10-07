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
* [트러블슈팅](troubleshooting/) - 운영 중 겪은 문제의 증상, 조사, 원인, 조치 사례.
* [환경](environments/) - 배포 대상 VPS와 public 운영 메타데이터.
* [도구](tooling/) - 프로젝트 개발과 운영을 지원하는 도구 및 skill.

# 핵심 개념

* [Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md) - 2026-09-11 저장소 정적 리뷰와 운영 확인 항목, 개선 우선순위.

* [로컬 우선 인프라 재구성](spec/0001-local-first-infra.md) - 단계 0~5 구현과 단계 6~8 후속 작업의 범위와 순서.
* [Jenkins가 VPS에서 이미지를 빌드한다](adr/0006-jenkins-builds-on-vps.md) - 빌드를 외부 CI로 넘기지 않는 근거와 리소스 실측.
* [프로젝트별 독립 Compose](adr/0007-per-project-compose.md) - 각 프로젝트가 자기 레포에서 compose와 이미지를 소유한다.
* [nginx 설정의 환경 템플릿화](adr/0008-nginx-env-templates.md) - envsubst 템플릿 한 벌로 로컬과 VPS를 커버한다.
* [Jenkins 설정을 코드로 관리](adr/0009-jenkins-config-as-code.md) - JCasC와 job-dsl로 설정과 Job을 레포에서 관리한다.
* [SOPS 기반 secret 관리](adr/0010-sops-secrets.md) - secret을 암호화해 레포에 커밋하고 복호화 key만 각 환경에 둔다.
* [인증서 갱신을 컨테이너 안에서 끝낸다](adr/0011-certbot-container-renewal.md) - systemd timer 대신 상주 certbot과 nginx 일일 reload를 쓴다.
* [빌드 결과를 Shared Library로 Mattermost에 알린다](adr/0012-mattermost-build-notification.md) - 모든 Jenkins job이 `notifyMattermost()`로 성공·실패를 알린다.
* [DB 스키마 ERD를 Liam으로 빌드해 nginx에서 정적으로 서빙한다](adr/0013-liam-erd-static-hosting.md) - 프로젝트 Jenkins job이 ERD를 빌드해 erd-site 볼륨에 넣고 nginx가 Basic Auth 뒤에서 서빙한다.
* [vps-info는 multibranch job으로 PR을 검증하고 main에서만 배포한다](adr/0014-multibranch-pr-ci.md) - PR마다 Test를 돌려 필수 check로 보고하고, 배포 stage는 main 빌드에서만 실행한다.
* [vps-info multibranch가 15분마다 스캔해 유실된 webhook을 보완한다](adr/0015-multibranch-periodic-scan.md) - webhook은 자동 재시도가 없어, 놓친 PR을 주기 스캔으로 잡는다.
* [관측 스택을 VPS에 셀프호스팅하고 Alloy 하나로 수집한다](adr/0016-self-hosted-observability.md) - Grafana·Prometheus·Loki·Tempo를 별도 Compose project로 띄우고 Alloy 하나가 수집한다.
* [외부 요청의 trace는 nginx가 시작한다](adr/0017-nginx-starts-traces.md) - nginx가 trace를 시작해 traceparent로 전파하고, 앱은 이어받기만 한다.
* [PR 생성 webhook이 유실되어 PR이 Jenkins에 나타나지 않는다](troubleshooting/webhook-pr-event-lost.md) - 연결 단계 실패로 PR #3만 누락된 사례의 조사 과정과 진단 순서.
* [관측 스택](services/observability.md) - Grafana·Prometheus·Loki·Tempo·Alloy로 메트릭·로그·트레이스를 모은다.
* [ERD 서빙 (Liam ERD)](services/erd.md) - 프로젝트 DB 스키마의 ER 다이어그램을 erd 서브도메인에서 정적 파일로 제공한다.
* [GitHub Actions 검증](services/github-actions-deploy.md) - 폐기된 SSH 배포 경로와 현재 검증 workflow.
* [Jenkins 배포](services/jenkins-deploy.md) - VPS 내부 Jenkins가 GitHub webhook을 받아 Docker Compose 배포를 실행한다.
* [vps-info (Signal Archive)](services/vps-info.md) - 자기 레포에서 compose와 Jenkinsfile을 소유하는 첫 외부 프로젝트.
* [nginx 리버스 프록시](services/nginx.md) - VPS의 public HTTP/HTTPS 진입점.
* [공용 인프라 포털](services/portal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
* [Frontend Design Skills](tooling/frontend-design-skills.md) - 포털과 frontend 작업을 위해 project scope로 설치된 Codex frontend design skill set.
* [시스템 아키텍처 개요](architecture/system-overview.md) - Hostinger VPS 1대에서 Jenkins, nginx, Docker Compose, PostgreSQL, Redis가 연결되는 전체 구조.
* [공용 인프라 포털 MVP 아키텍처](architecture/portal-dashboard-proposal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털 MVP 구조.
* [Hostinger VPS](environments/hostinger-vps.md) - 현재 인프라가 배포될 VPS와 public 운영 메타데이터.
* [초기 배포 검증](runbooks/initial-deployment-validation.md) - 첫 인프라 배포 성공 기준.
* [로컬 우선 인프라 인수 절차](runbooks/local-first-handover.md) - spec 0001 단계 0~5 구현 후 사용자 작업과 로컬 검증 명령.
