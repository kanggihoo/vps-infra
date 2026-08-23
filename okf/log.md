# 변경 기록

## 2026-08-23
* **삭제**: `docs/superpowers/`와 `references/` 그룹을 제거했다. 원본 설계 문서가 traefik + GitHub Actions 시절 내용이라 이미 폐기된 구조를 서술하고 있었고, 이를 가리키던 reference concept와 `# Citations` 블록 12개도 함께 정리했다.
* **정리**: ADR 파일명을 작성 시점 순 `0001`~`0010`으로 통일하고 inbound 링크를 갱신했다. 이전에는 초기 결정 5개가 번호 없는 slug 이름이었다.
* **생성**: [로컬 우선 인프라 재구성](/spec/0001-local-first-infra.md) spec을 추가하고, seam 3개(스크립트 / 기동된 스택 HTTP / SOPS 왕복)와 8단계 작업 순서를 기록했다.
* **정리**: 고아 certbot container와 `hello-world` 잔재를 제거했다. 원인은 `docker compose run` 시 `--entrypoint certbot` 누락으로 `Cmd` 인자가 무시되고 renew 루프가 중복 실행된 것이다.
* **이동**: 번들 위치를 `.okf/`에서 `okf/`로, `decisions/`를 `adr/`로 옮기고 참조 경로를 갱신했다.
* **생성**: [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md) - GHCR 대신 VPS 빌드를 유지하는 근거와 리소스 실측을 기록했다.
* **생성**: [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md) - 중앙집중 `compose.yml` 방침을 뒤집고, Quartz 이미지화와 rollback 확보를 기록했다.
* **생성**: [nginx 설정의 환경 템플릿화](/adr/0008-nginx-env-templates.md) - envsubst 기반 로컬/VPS 공용 설정을 기록했다.
* **생성**: [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md) - JCasC/job-dsl 도입과 GUI 편집 무효화 제약을 기록했다.
* **생성**: [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md) - 암호화 secret을 레포에 두는 방식과 Vault 거절 근거를 기록했다.
* **갱신**: [Jenkins 내부 배포](/adr/0004-jenkins-deployment.md)에서 `/opt/vps-infra` 경로 전제를 걷어내고 대체된 항목을 명시했다.
* **갱신**: [SSH Git-Pull 배포](/adr/0001-ssh-git-pull-deployment.md)를 폐기로 표시하고, Actions를 검증 전용으로 전환하는 근거를 기록했다.
* **갱신**: [시스템 아키텍처 개요](/architecture/system-overview.md)의 운영 파일 경계에서 traefik 잔재를 제거하고 nginx 템플릿·SOPS·age key를 반영했다.

## 2026-07-03
* **갱신**: [공용 인프라 포털](/services/portal.md)에 Mintlify-inspired dark 기본 theme, skill source URL, install command block UI를 추가한 내용을 기록했다.
* **갱신**: [공용 인프라 포털](/services/portal.md)의 frontend stack을 Tailwind CSS v4, shadcn/ui, lucide-react, Pretendard 기반으로 전환한 내용을 기록했다.
* **생성**: [Frontend Design Skills](/services/frontend-design-skills.md) concept를 추가하고, project scope Codex frontend design skill set과 DESIGN.md workflow 참고 문서를 기록했다.
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
* **생성**: 원본 설계 문서를 가리키는 VPS 인프라 GitHub Actions 배포 설계 reference concept를 추가했다. (2026-08-23 삭제됨)
