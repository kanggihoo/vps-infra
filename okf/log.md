# 변경 기록

## 2026-09-28
* **생성**: [vps-info](/services/vps-info.md) 배포를 연결했다. Jenkins 이미지에 sops를 넣고 `vps-info` Job, `info` 서브도메인, `CHALLENGE_DOMAINS`를 추가했다. spec 0001 단계 8에 해당한다.
* **수정**: Jenkinsfile의 `DEPLOY_SHA` 대입이 `script` 블록 밖에 있어 2026-09-13 이후 vps-infra 파이프라인이 컴파일 단계에서 실패하던 문제를 고쳤다.
* **정리**: `quartz-deploy` Job 정의와 `QUARTZ_SCM_URL`을 제거했다.
* **갱신**: VPS Jenkins가 JCasC 이미지로 동작함을 확인해(`CASC_JENKINS_CONFIG` 설정됨) [인수 절차](/runbooks/local-first-handover.md)의 단계 6-b를 완료로 바꿨다.

## 2026-09-13
* **생성**: [Jenkins·nginx 리뷰 보완](/spec/0002-infra-review-remediation.md) 스펙을 추가했다.
* **구현**: nginx 후보 설정 검사·강제 재생성, portal 경로 healthcheck, private notes 캐시 정책, Jenkins 누적 SHA 배포 상태, systemd 기반 인증서 갱신을 추가했다.
* **갱신**: Jenkins controller executor를 전역 1개로 제한하고, host BuildKit 자원 관측 조건을 ADR 0006에 기록했다.

## 2026-09-11
* **생성**: [Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md)에 설정 반영, 인증서 갱신, 캐시·인증 기본값, 배포 SHA, Jenkins 권한 경계와 운영 개선안을 기록했다. VPS 실측과 저장소 정적 분석을 구분했다.

## 2026-08-25
* **동기화**: 현재 코드 기준으로 시스템 아키텍처, nginx/Jenkins 서비스, VPS 환경, 초기 배포 검증 문서의 경로·프록시·SOPS 설명을 갱신했다. 과거 SSH 배포와 Traefik 내용은 역사 기록으로 구분했다.
* **이동**: `Frontend Design Skills`를 runtime service가 아닌 project tooling 개념으로 보고 `/tooling/`으로 이동했으며, 실제 `.agents/skills/` 목록과 동기화했다.
* **갱신**: `INFRA.md`를 현재 Compose, Jenkins, nginx template, SOPS 구조 기준의 현황 및 신규 서비스 추가 가이드로 재작성했다.

## 2026-08-23
* **생성**: [로컬 우선 인프라 인수 절차](/runbooks/local-first-handover.md) 런북을 추가했다. spec 0001 단계 0~5을 구현하면서, 사용자만 할 수 있는 작업(age key 생성, 실제 secret 암호화)과 로컬 검증 명령, 미구현 단계 6~8의 선행 조건을 정리했다.
* **구현**: spec 0001 단계 0~5을 구현했다. 배포 대상 판정을 셸 스크립트로 내리고(빈 diff는 판정 불가로 실패), nginx conf를 envsubst 템플릿으로 바꿔 로컬 HTTP 기동을 가능하게 했고, SOPS 배선과 Jenkins JCasC/job-dsl을 추가했다. 로컬 Jenkins가 빈 volume에서 기동만으로 Job을 복원하고 파이프라인 전체가 통과함을 확인했다. 단계 6~8은 VPS 접근과 외부 레포가 필요해 미구현이다.
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
* **생성**: [Frontend Design Skills](/tooling/frontend-design-skills.md) concept를 추가하고, project scope Codex frontend design skill set과 DESIGN.md workflow 참고 문서를 기록했다.
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
* **생성**: [GitHub Actions 배포](/services/github-actions-deploy.md), Traefik 리버스 프록시(2026-07 nginx 전환 시 삭제됨), [PostgreSQL](/services/postgresql.md), [Redis](/services/redis.md), [whoami Health Target](/services/whoami.md) 서비스 개념을 추가했다.
* **생성**: 배포 방식, 라우팅 방식, 데이터 서비스 격리, 재부팅 복구 결정을 추가했다.
* **생성**: [초기 배포 검증](/runbooks/initial-deployment-validation.md), [장애 진단](/runbooks/failure-diagnosis.md) 런북을 추가했다.
* **생성**: 원본 설계 문서를 가리키는 VPS 인프라 GitHub Actions 배포 설계 reference concept를 추가했다. (2026-08-23 삭제됨)
