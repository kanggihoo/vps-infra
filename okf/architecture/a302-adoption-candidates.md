---
type: Review
title: A302 인프라 도입 후보 검토
description: 종료된 S15P31A302(Fit Dining) 인프라와 12일 공개 운영 결과, GitLab CI/CD에서 이 VPS와 Jenkins 파이프라인에 가져올 만한 항목, 우선순위, 적용 방법, 가져오지 않을 항목. 미확정 후보다.
tags: [review, backup, docker, ci, cd, jenkins, postgresql, host, observability, alerting, nginx, security, runbook]
timestamp: 2026-11-17T00:00:00+09:00
---

# 상태

확정된 결정이 아니라 후보 목록이다. 항목을 진행하기로 정하면 결정은
[ADR](/adr/)로, 구현 범위는 [스펙](/spec/)으로 옮기고 이 문서에서는 그 항목을
"옮김"으로 표시한다.

비교 기준은 A302 레포(`docs/infra/design.md`, `docs/infra/runbooks/`, `infra/`)와 이 레포다.

| 갱신일 | 본 범위 | 추가한 후보 |
|---|---|---|
| 2026-10-22 | A302 설계와 `infra/` | 1~8 |
| 2026-10-23 | A302의 관측(`infra/obs/`)과 외부 감시(`infra/ops/`) | 9~12 |
| 2026-11-17 | A302 종료 시점(`41a8214`). 10-23 이후 인프라 관련 커밋 83개: 런북 RB-01~14, 복원 리허설 3회, 엣지 보안 헤더, 메타데이터 차단, 알림 조정 | 13~18, 기존 후보 보강 |
| 2026-11-17 | A302 GitLab CI/CD(`.gitlab-ci.yml`, `infra/deploy/`, `infra/ci/`)와 이 레포·vps-info의 Jenkins 파이프라인 | 19~26 |

A302는 2026-11-06 첫 공개, 11-18 서비스 종료로 공개 운영이 12일이었고 2026-11-17 마지막
커밋으로 프로젝트가 끝났다. 앞으로 A302 쪽 변경은 없으므로 이 문서가 마지막 비교다.

이 레포는 2026-10-09 이후 커밋이 없어 1~12번 중 적용된 것은 없다. VPS에 손으로 해 둔
설정은 확인하지 않았다.

## 2026-11-22 파이프라인 반영

- **6번 옮김**. Gitleaks는 CI에서 커밋 범위를 검사하고 Lefthook은 staged 변경을 검사한다.
- **19·23번 옮김**. 같은 Actions 실행 안에서 CI gate 뒤 게시·배포를 연결하고, PR만 이전 실행을 취소한다.
- **21·22번 옮김**. Portal의 SHA 태그, digest 배포·수동 롤백, nginx 경유 SHA 확인을 코드에 반영했다. VPS 전환은 별도 설정 후 적용된다.
- **26번 부분 반영**. 기존 배포 잠금 유지, 게시 SHA/digest와 현재 Portal 적용 상태 기록. 서버의 상세 배포 이력은 후보로 남는다.

전환 및 검증 절차는 [배포 문서](/services/deploy.md)에 있다. 아래 내용은 A302 종료 시점의 비교 기록이다.

# 왜 A302를 보는가

A302 설계는 선배 팀 두 곳에 공통으로 없던 것으로 컨테이너 메모리 제한, 로그
로테이션, 이미지 prune, 서버 밖 백업을 꼽고 전부 넣었다. 이 레포는 같은 기준에서
메모리 제한이 Jenkins와 관측 스택에만 있고 나머지 셋은 없다.

10-22 검토 때는 설계와 스크립트만 있었다. 종료 시점에는 실제 운영에서 돌려 본 결과가 있다:
실데이터 복원 리허설과 RTO, 운영 중 바꾼 알림 조건, 배포·reload 순간의 끊김 실측, 각 런북의
"따라 해 본 범위". 그래서 이번 갱신은 후보를 늘리는 것보다 "실제로 효과가 있었던 것"으로
우선순위를 다시 매기는 데 무게를 둔다.

# 우선순위

종료 시점 기준 추천 순서다. 작업량이 작고 사고를 미리 드러내는 것을 먼저 둔다.

| 단계 | 항목 | 이유 |
|---|---|---|
| 먼저 | 9 인증서 만료 알림, 15 컨테이너 사라짐 알림 | 지표가 이미 있어 Grafana 알림 규칙만 더하면 된다 |
| 먼저 | 13 nginx 보안 헤더 | 템플릿 몇 줄. 현재 보안 헤더가 하나도 없다 |
| 먼저 | 1 로그 로테이션·prune, 2 디스크 검사 | Jenkins가 VPS에서 빌드해 디스크가 계속 찬다. 디스크가 차면 전부 멈춘다 |
| 먼저 | 19 검증을 통과한 커밋만 배포 | 지금은 GitHub Actions 검증과 Jenkins 배포가 같은 push에 동시에 돌아 검증이 배포를 막지 못한다 |
| 다음 | 3 R2 암호화 백업, 16 재구축 표, 20 마이그레이션 전 덤프 | `signal_archive`가 VPS 볼륨 한 곳뿐이다. A302에서 가장 많이 다듬은 영역이다 |
| 다음 | 10 VPS 밖 감시 | VPS가 통째로 죽으면 지금은 아무도 알리지 않는다 |
| 다음 | 21 SHA 태그 이미지와 롤백, 22 배포 SHA 확인 | 지금은 직전 이미지가 남지 않아 되돌리려면 revert 커밋을 다시 빌드해야 한다 |
| 나중 | 4, 5~7, 11, 12, 17, 18, 23~26 | 효과는 있으나 급하지 않다 |
| 확인 후 | 8, 14 | 8은 작업량이 크고, 14는 Hostinger에 메타데이터 서비스가 있는지부터 모른다 |

# 후보

| 순서 | 항목 | A302 참고 | 작업량 |
|---|---|---|---|
| 1 | Docker 로그 로테이션과 이미지 prune 타이머 | `infra/host/docker-prune.sh`, `infra/host/conf/systemd/fit-docker-prune.*`, RB-04 | 작음 |
| 2 | 배포 전 디스크 여유 검사 | `infra/deploy/preflight.sh` | 아주 작음 |
| 3 | Cloudflare R2 암호화 백업 | `infra/backup/`, RB-06 | 중간 |
| 4 | 프로젝트별 DB·role 멱등 생성 | `infra/data/ensure-databases.sh` | 작음 |
| 5 | CI shellcheck | `.gitlab-ci.yml`의 `lint:shell` | 작음 |
| 6 | CI·pre-commit gitleaks | `lint:secrets`, `infra/ci/pre-commit-secrets.sh` | 작음 |
| 7 | CI 포트 바인딩 검사 | `infra/ci/ports_invariant.py` | 작음 |
| 8 | 서버 설정 스크립트화 | `infra/host/bootstrap.sh`, `infra/host/verify-host.sh` | 중간~큼 |
| 9 | 인증서 만료 알림 | `infra/ops/prometheus/rules/probes.yml`, RB-05 | 아주 작음 |
| 10 | VPS 밖에서 보는 감시 | `infra/ops/` (B가 A를 밖에서 본다) | 작음 |
| 11 | 바깥에서 하는 포트 노출 검사 | `infra/ops/port-audit.py` | 작음 |
| 12 | 알림마다 런북 링크, 런북 형식 | `infra/ci/check_alerts.py`, `docs/infra/runbooks/README.md` | 작음 |
| 13 | nginx 공통 보안 헤더와 HSTS | `infra/edge/conf/Caddyfile`, 설계의 엣지 헤더 절, RB-05 | 작음 |
| 14 | 컨테이너의 클라우드 메타데이터 접근 차단 | `infra/host/block-imds.sh` | 아주 작음(확인 후) |
| 15 | exporter 없는 컨테이너의 사라짐 알림 | `infra/obs/prometheus/rules/data.yml`의 `FitRedis*Down` | 아주 작음 |
| 16 | 재구축(DR) 표와 런북 | RB-12 | 작음(표), 중간(리허설) |
| 17 | secret별 교체 절차 표 | RB-08 | 작음 |
| 18 | 설정이 바뀐 배포에서만 nginx 재생성 | RB-02 F절, RB-05의 끊김 실측 | 작음 |
| 19 | 검증을 통과한 커밋만 배포 | `.gitlab-ci.yml`의 verify → build → deploy `needs` 사슬 | 작음 |
| 20 | 마이그레이션 전 덤프(vps-info) | `deploy.sh`의 사전 덤프, `pg-backup.sh predeploy` | 작음 |
| 21 | SHA 태그 이미지와 직전 이미지 롤백 | `build-images.sh`, `rollback.sh`, 상태 파일의 `PREVIOUS_SHA` | 중간 |
| 22 | 스모크가 배포된 SHA를 확인 | `smoke.sh --sha`, `/api/v1/version` | 작음 |
| 23 | PR 빌드만 이전 빌드 취소 | `interruptible`을 verify 잡에만 | 아주 작음 |
| 24 | Jenkinsfile 구조 시험 | `infra/ci/tests/test_pipeline_structure.py` | 작음 |
| 25 | 빌드 베이스 이미지 버전 고정 | `.gitlab-ci.yml` 변수, `tool-images.sh`, `test_tool_images_sync.py` | 아주 작음 |
| 26 | 배포 잠금과 이력 | `lib.sh`의 `acquire_lock`, `history-<환경>.log`, `SKIP_VERIFY=<사유>` | 작음 |

루트 `compose.yml`의 nginx, portal, postgres, redis에 `mem_limit`을 다는 일은
1번과 함께 할 수 있다.

## 1. 로그 로테이션과 이미지 prune

A302는 Docker 데몬의 `json-file` 로그를 10MB×3으로 제한하고, systemd 타이머가
주 1회 쓰지 않는 이미지와 빌드 캐시를 지운다. 앱 이미지는 최근 5개를 남기고
볼륨은 지우지 않는다.

이 VPS는 Jenkins가 이미지를 직접 빌드한다([ADR 0006](/adr/0006-jenkins-builds-on-vps.md)).
그래서 이미지와 BuildKit 캐시가 배포마다 쌓이고, 디스크가 차면 Postgres와 nginx가
함께 멈춘다. 적용 전에 VPS에서 `docker system df`로 현재 누적량을 본다.

적용 방법 후보는 두 가지다. 호스트 systemd 타이머는 A302 파일을 거의 그대로 쓴다.
[ADR 0011](/adr/0011-certbot-container-renewal.md)처럼 호스트 timer를 피하려면
Jenkins 주기 job으로 돌리고 `notifyMattermost()`로 결과를 받는다.

종료 시점 보강: A302의 prune 스크립트는 운영 끝까지 대상 이미지 이름(`ai`)만 늘었고 구조는
그대로였다. RB-04는 디스크를 "늘어나는 것별"로 나눠 조치를 적었다(이미지와 빌드 캐시, CI 캐시
볼륨, 데이터, 시스템 로그). 이 레포에서는 이미지·BuildKit 캐시, Jenkins 작업 공간과 빌드 기록,
Loki·Prometheus 보관 데이터, Postgres 볼륨이 그 목록이 된다. 1번을 적용할 때
[장애 진단](/runbooks/failure-diagnosis.md)에 이 목록과 각각의 확인 명령을 함께 적는다.

## 2. 배포 전 디스크 여유 검사

A302 `preflight.sh`는 디스크 여유가 기본 5GB 미만이면 배포를 멈춘다.
`scripts/deploy.sh` 앞부분의 기존 검사 옆에 같은 검사를 둔다. 1번과 짝이다.

## 3. Cloudflare R2 암호화 백업

현재 공용 Postgres의 `signal_archive`([vps-info](/services/vps-info.md))는 VPS 볼륨
한 곳에만 있다.

흐름:

1. Jenkins 주기 job이 DB마다 `pg_dump -Fc`로 덤프한다.
2. 네트워크 없는 임시 Postgres 컨테이너에 복원해 public 테이블 수가 원본과 같은지
   본다(A302 `verify-dump.sh` 방식). 다르면 올리지 않고 실패로 끝낸다.
3. 백업 전용 age 공개키로 암호화한다.
4. `rclone`으로 R2 버킷에 올린다. API 토큰은 그 버킷에만 권한을 준다.
5. 보관 기간은 R2 객체 수명주기 규칙으로 지운다. 삭제 스크립트를 두지 않는다.
6. 성공·실패는 `notifyMattermost()`([ADR 0012](/adr/0012-mattermost-build-notification.md))가 알린다.
7. 가끔 노트북에서 내려받아 복호화·복원해 본다.

age 키는 [SOPS 키](/adr/0010-sops-secrets.md)와 분리한다. SOPS 개인키는 배포 때문에
VPS와 Jenkins credential에 있으므로, 같은 키로 백업을 암호화하면 VPS 침해 시
백업도 풀린다. A302도 백업 개인키를 서버에 두지 않는다.

R2를 고른 이유: 무료 10GB, egress 무료, 비활성 일시정지 없음, S3 호환 API.
Supabase 무료 플랜은 DB 500MB·Storage 1GB이고 1주 비활성 시 프로젝트가 정지되며
자체 백업이 없다. DB에 복원해 두는 방식은 데이터를 평문으로 외부에 둔다.
수치는 제3자 가격 정리 기준이므로 적용 전에 공식 가격 페이지로 확인한다.

남은 약점: R2 토큰에 쓰기 전용 권한이 없는 것으로 보여, VPS가 침해되면 같은 토큰으로
백업을 지울 수 있다. A302는 받는 쪽 SSH를 `rrsync -wo`로 막아 이를 해결했다.
R2 버킷 잠금(보관 기간 동안 삭제 금지)으로 막을 수 있는지 확인이 필요하다.
안 되면 노트북에 최신 사본 1벌을 둔다.

### A302 복원 리허설에서 배운 것

A302는 복원 리허설을 세 번 했다(`infra/backup/README.md`의 리허설 기록).

| 회차 | 날짜 | 대상 | 결과 |
|---|---|---|---|
| #1 | 2026-10-22 | 테이블 0개인 prod 덤프 | 복호화·복원은 됐지만 빈 DB라 데이터는 확인하지 못했다 |
| #2 | 2026-10-27 | 테이블 6개, 행이 거의 없는 dev 덤프 | 7초. 실제 데이터 크기의 RTO가 아니었다 |
| #3 | 2026-11-10 | prod 실데이터(테이블 30개, 덤프 약 138MiB) | DB 복원 약 30초(복원 17초 + 내려받기 12.6초), 덤프 33초 |

이 레포에 가져올 점:

- **첫 리허설부터 실데이터로 한다.** #1·#2는 "파이프라인이 끝까지 돈다"만 증명했다.
  `signal_archive`는 이미 데이터가 있으므로 처음부터 실제 크기로 RTO를 잰다.
- **덤프에는 role 권한이 들어간다.** A302는 팀원용 읽기 전용 role을 더하자 prod 덤프에 그
  role의 GRANT가 들어가, 복원 검증 컨테이너에도 같은 role을 먼저 만들어야 했다
  (`verify-dump.sh`가 role 목록을 만든다). 이 레포에서 4번으로 role을 만들면 2단계 검증
  컨테이너에도 같은 role 목록을 만든다. role 목록을 한 곳에 두고 둘이 함께 읽게 한다.
- **복원 스크립트는 오류 원인을 가린다.** A302 `restore-check.sh`는 처음에 모든 복호화 실패를
  "개인키가 수신자가 아니다"로 보고해, 실제로는 파일 경로 문제(Windows의 `age.exe`가 Git Bash
  경로를 못 연다)인 것을 키 문제로 오진하게 했다. 이후 백업 파일 없음, 키 파일 없음, 수신자
  아님, 그 밖의 age 원문 오류로 나눴다. 7단계를 스크립트로 만들 때 처음부터 이렇게 나눈다.
- **노트북에서 이진 파일을 받을 때 셸 리다이렉트를 조심한다.** A302는 PowerShell `>`로 받은
  암호화 파일이 글자로 바뀌어 깨졌다. macOS 셸에서는 해당 없지만 `rclone copy`로 받는다.

## 4. 프로젝트별 DB·role 멱등 생성

A302 `ensure-databases.sh`는 DB와 role을 몇 번 실행해도 같은 결과로 만들고,
role 비밀번호를 env 값으로 다시 맞추며, 각 role이 자기 DB에만 접속하게 한다.
Postgres 이미지의 init 스크립트는 빈 볼륨에서 한 번만 돌아서 쓰지 않는다.

[PostgreSQL](/services/postgresql.md) 문서의 "향후 서비스별 DB와 role 분리"가 이것이다.
`signal_archive` DB와 role은 레포 어디에서도 만들지 않아 VPS에서 수동으로 만든 것으로
보인다. 첫 대상은 이 DB를 코드로 고정하는 것이다.

종료 시점 보강: A302는 운영 중 읽기 전용 role을 둘 더했다(AI API용, 팀원용 그룹). 읽기 전용
role에는 같은 스크립트가 `CONNECTION LIMIT 6`, `statement_timeout = '10s'`,
`default_transaction_read_only = on`을 함께 건다. 이 레포에서 Grafana PostgreSQL
datasource나 수동 조회용 계정이 필요해지면 같은 세 설정으로 만든다. 지금은 필요 없다.

## 5~7. CI 검사

현재 [GitHub Actions 검증](/services/github-actions-deploy.md)은 compose 문법, nginx
local/live 렌더링, 대상 선택 테스트, SOPS 검사를 한다. 추가 후보:

- shellcheck: `scripts/`와 `jenkins/start.sh`의 bash가 정적 검사 없이 배포를 돌린다.
- gitleaks: `check-sops.sh`는 `secrets/` 안 파일의 암호화 여부만 본다. 다른 파일에
  붙여 넣은 토큰과, 추가했다 지운 이력은 gitleaks가 잡는다.
- 포트 바인딩 검사: `docker compose config` 결과에서 게시 포트가 `127.0.0.1`인지 보고
  nginx 80/443만 예외로 둔다. Docker가 게시한 포트는 ufw를 우회한다. 이 레포의 compose만
  보므로 프로젝트 레포의 compose는 따로 막아야 한다.

hadolint(`jenkins/Dockerfile`, `portal/Dockerfile`, `tools/Dockerfile`), yamllint,
CI를 노트북에서 똑같이 돌리는 러너(`infra/ci/run-local-checks.sh`)는 우선순위가 낮다.

## 8. 서버 설정 스크립트화

A302는 `bootstrap.sh`가 SSH 키 전용·root 금지, fail2ban, ufw, swap, 시간대, 자동
보안 업데이트를 멱등하게 설정하고, `verify-host.sh`가 PASS/FAIL만 출력한다.
Ubuntu 22.04·24.04 컨테이너에서 설정을 망가뜨려 verify가 잡고 bootstrap이 고치는지
시험했다.

이 레포는 Compose·nginx·Jenkins는 코드로 복구되지만 그 밑의 호스트 설정은 레포에 없다.

종료 시점 보강: A302는 운영 중 호스트 설정을 세 번 바꿨고(swap 2GB→4GB, CI용 ufw 규칙,
메타데이터 차단) 매번 `bootstrap.sh`와 `verify-host.sh`를 함께 고쳤다. ufw 검사는 "허용
규칙이 설계와 정확히 같다"로 비교해, 손으로 연 규칙도 FAIL로 드러난다. 전체 스크립트화가
크면 `verify-host.sh`에 해당하는 읽기 전용 점검(ufw 규칙 목록, SSH 설정, swap)만 먼저 만든다.

## 9. 인증서 만료 알림

A302는 B가 밖에서 TLS 연결로 만료일을 읽어 14일 미만이면 warning, 7일 미만이면
critical을 낸다.

이 레포는 Alloy blackbox가 health·portal·jenkins를 `https://`로 이미 프로브하므로
`probe_ssl_earliest_cert_expiry` 지표가 있다. 빠진 것은
`observability/grafana/provisioning/alerting/alerting.yaml`의 알림 규칙 하나다.
2026-09-28까지 자동 갱신 주체가 없던 일([ADR 0011](/adr/0011-certbot-container-renewal.md))을
이 알림이 만료 전에 드러냈을 것이다.

## 10. VPS 밖에서 보는 감시

A302가 B를 감시자로 둔 이유는 A가 통째로 죽으면 A 안의 Prometheus·Alertmanager도
함께 죽어 아무도 알리지 않기 때문이다. B는 A의 HTTPS 응답, 80·443 도달, Prometheus·
Alertmanager 생존을 밖에서 본다.

이 레포도 프로브, Grafana, 알림 발송이 모두 같은 VPS 안에 있다. VPS가 멈추면
"서브도메인 응답 실패" 알림을 보낼 Grafana도 멈춘다.

B가 없으므로 대체 후보는 둘이다.

- 외부 업타임 서비스(UptimeRobot 등)가 `health` 서브도메인을 밖에서 프로브한다.
- dead man's switch: Grafana가 외부 서비스(Healthchecks.io 등)에 주기적으로 신호를 보내고,
  신호가 끊기면 그 서비스가 알린다. 감시하는 쪽의 생존을 보는 A302의 `a-prometheus`·
  `a-alertmanager` 프로브와 같은 목적이다.

## 11. 바깥에서 하는 포트 노출 검사

A302 `port-audit.py`(표준 라이브러리만)는 B에서 A로 TCP 연결을 시도해 22·80·443 외에
열린 포트를 찾는다. 15분마다 주요 포트를, 매일 전체 포트를 본다.

7번 CI 검사는 이 레포의 compose만 본다. 바깥 스캔은 vps-info 같은 프로젝트 레포의 compose나
수동 `docker run`이 연 포트까지 실제 상태로 잡는다. B 대신 GitHub Actions `schedule`로
하루 한 번 돌린다. 대상은 이 VPS 하나로 고정한다.

## 12. 알림마다 런북 링크, 런북 형식

A302 `check_alerts.py`는 모든 알림에 severity·summary·description·runbook이 있는지 CI에서
검사한다. 이 레포의 알림은 Grafana 관리형이라 `promtool test rules`를 그대로 쓸 수 없다.
대신 각 알림 annotation에 [장애 진단](/runbooks/failure-diagnosis.md) 런북 링크를 단다.

종료 시점 보강: A302는 10-27~10-28에 런북 RB-01~14를 쓰고 알림 이름마다 런북 번호를 매긴 표를
README에 뒀다. 모든 런북이 같은 약속을 따른다.

- 순서: 증상 → 값을 출력하지 않는 확인 명령 → 원인별 조치 → 되돌리기 → 이 런북을 따라 해 본 범위.
- 머리에 "검증 기준"(어느 커밋, 어느 날짜의 서버에서 확인했는지)을 적고 스크립트가 바뀌면 다시 확인한다.
- 직접 확인한 것과 확인하지 못한 것을 (확인)·(미확인)으로 구분한다.
- 따라 해 보지 않은 런북은 그렇다고 머리에 적는다(RB-12 "서버에서 한 번도 따라 해 보지 않았다").

이 레포 알림은 4개(디스크, 메모리, 서브도메인 응답 실패, Jenkins 큐)이므로, 장애 진단 런북에
알림별 절을 넷 만들고 각 알림 annotation이 그 절을 가리키게 하면 된다. 위 약속 중 "검증 기준"과
"따라 해 본 범위"는 OKF 런북 형식에 그대로 넣을 수 있다.

## 13. nginx 공통 보안 헤더와 HSTS

A302 엣지는 모든 응답에 `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy`, `Permissions-Policy`, CSP를 붙이고 `Server`·`X-Powered-By`를 지웠다.
HSTS는 운영 인증서가 확정된 뒤 2026-11-03에 `max-age=31536000`(`includeSubDomains`,
`preload` 없음)으로 켰다. staging 인증서 단계에서 켜면 브라우저가 거부해 시험이 막히기 때문이다.

이 레포 nginx 템플릿에는 보안 헤더가 없다. `add_header`는 notes·erd 템플릿의 `Cache-Control`뿐이고
`server_tokens`도 기본값(버전 노출)이다.

적용 방법:

- `nginx.conf`의 `http` 블록에 `server_tokens off;`를 둔다.
- 공통 헤더(`nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`)를 snippet 파일 하나에
  두고 각 `server`에서 include한다.
- **nginx `add_header` 상속 함정:** 하위 블록에 `add_header`가 하나라도 있으면 상위 블록의
  `add_header`를 상속하지 않는다. notes·erd 템플릿의 location은 `Cache-Control`을 붙이므로
  그 location에서는 공통 헤더가 빠진다. 그 location에도 snippet을 include한다.
  `scripts/test-routing.sh`에 서브도메인별 응답 헤더 확인을 더해 빠진 곳을 잡는다.
- `X-Frame-Options`: Jenkins와 Grafana는 자기 헤더를 보낸다. 같은 헤더가 두 번 나가지 않게
  자체 헤더가 없는 서비스(portal, erd, notes 등)에만 붙인다.
- HSTS: 이 레포는 이미 운영 인증서라 조건은 된다. `includeSubDomains`는 `kkh-hub.tech` 아래
  모든 서브도메인이 HTTPS여야 하고, 한 번 내보내면 `max-age` 동안 이미 접속한 브라우저에서
  되돌릴 수 없다(A302 RB-05). 짧은 `max-age`로 시작해 늘리는 것을 제안한다.
- CSP는 공통으로 두지 않는다. A302는 앱이 하나라 허용 목록 하나로 됐지만, 이 레포는
  서브도메인마다 앱이 다르고 Jenkins·Grafana는 자체 CSP를 낸다. 필요한 앱이 스스로 낸다.

## 14. 컨테이너의 클라우드 메타데이터 접근 차단

A302는 2026-11-02 EC2에서 컨테이너가 `169.254.169.254`(IMDSv2) 토큰 발급에 200으로 닿는 것을
확인했다. MR 코드를 도는 CI 러너가 인스턴스의 역할 자격 증명과 user-data를 읽을 수 있다는
뜻이라, `DOCKER-USER` 체인에 그 주소로 가는 컨테이너발 패킷을 버리는 규칙을 넣고 부팅·Docker
재시작 때 다시 넣는 systemd 유닛을 뒀다(`block-imds.sh`). 호스트 자신의 접근은 막지 않는다.

이 레포도 Jenkins가 PR 코드를 VPS에서 빌드·시험한다([ADR 0014](/adr/0014-multibranch-pr-ci.md)).
다만 Hostinger VPS는 EC2가 아니라 메타데이터 서비스가 있는지부터 모른다. 먼저 VPS의 컨테이너
안에서 그 주소로 짧은 timeout의 HTTP 요청을 보내 응답이 있는지 본다. 응답이 없으면 할 일이 없다.
응답이 있고 그 안에 자격 증명이나 user-data(초기 root 비밀번호 등)가 있으면 A302 스크립트를
그대로 쓴다.

## 15. exporter 없는 컨테이너의 사라짐 알림

A302는 Redis exporter 없이 cAdvisor 지표로 Redis 컨테이너가 사라진 것을 잡았다(2026-11-10).

```promql
absent(container_last_seen{name=~"fit-data-redis-prod-.*"}) and on() (up{job="cadvisor"} == 1)
```

뒤의 조건은 cAdvisor가 죽어 지표가 통째로 없을 때 울리지 않게 한다. 그때는 수집 대상 다운
알림이 따로 운다. 떠 있지만 응답하지 않는 경우는 잡지 못한다고 알림 설명에 적었다.

이 레포 알림 4개는 `vps-postgres`·`vps-redis` 중단을 직접 보지 않는다. 서브도메인 응답 실패는
앱의 health가 DB 없이도 200을 내면 못 잡는다. Alloy가 cAdvisor의 `container_last_seen`을 이미
허용 목록에 두므로(`observability/alloy/config.alloy`) Grafana 알림 규칙만 더하면 된다.
cAdvisor의 job 이름과 `name` label 형식은 Prometheus에서 확인한다.

같이 가져올 원칙: A302는 아직 지표를 내지 않는 대상의 `absent()` 알림이 계속 울려 진짜 알림을
가리자, "7일 안에 낸 적이 있는 지표가 사라졌을 때만" 울리게 바꿨다.

```promql
absent(x) and on() (count(last_over_time(x[7d])) > 0)
```

이 레포에서 `absent()` 알림을 만들 때 대상이 처음부터 지표를 내지 않을 수 있다면 같은 조건을 붙인다.

## 16. 재구축(DR) 표와 런북

A302 RB-12는 "무엇이 어디에 있어서 무엇이 되살아나나" 표로 시작한다. 데이터마다 백업 위치와
되살리는 도구를 적어, 사진처럼 백업은 있는데 되살리는 도구가 없는 빈칸을 드러냈다. 서버의 env
파일은 age로 암호화한 사본을 USB에 두고 수신자 2명이 복호화해 확인했다(2026-11-12). 이 런북은
서버에서 한 번도 따라 해 보지 않았고, 그 사실과 "알려진 빈칸"을 맨 위에 적었다.

이 레포는 표부터 만든다. 예상 행(실제 볼륨은 VPS에서 `docker volume ls`로 확인한다):

| 대상 | 지금 있는 곳 | 되살리는 방법 |
|---|---|---|
| compose, nginx, JCasC, 관측 설정 | git | clone 후 `scripts/deploy.sh` |
| secret | SOPS로 git | age 개인키가 있어야 한다 |
| SOPS age 개인키 | 노트북, VPS, Jenkins credential, GitHub Secrets | GitHub Secrets는 읽어 낼 수 없다. VPS 소실과 노트북 분실이 겹치면 잃는다 |
| `signal_archive` DB | VPS 볼륨만 | 3번 전까지 빈칸 |
| Jenkins 빌드 기록 | VPS 볼륨만 | 설정은 JCasC·job-dsl로 복구, 기록은 잃는다 |
| 인증서 | certbot 볼륨 | 재발급(Let's Encrypt 발급 한도 안에서) |
| Grafana·Prometheus·Loki·Tempo 데이터 | VPS 볼륨만 | 잃는다. 잃어도 되는지 정한다 |
| ERD 정적 파일 | erd-site 볼륨 | 프로젝트 Jenkins job이 다시 빌드 |

[ADR 0010](/adr/0010-sops-secrets.md)은 age 키 백업을 운영 요구사항으로 적었지만 어디에 두는지는
정하지 않았다. A302가 env 사본을 USB에 둔 것과 같은 이유로 SOPS 개인키의 오프라인 사본 위치를
이 표에 함께 정한다. 리허설(새 VPS에 처음부터 올리기)은 3번이 생긴 뒤에 한다.

## 17. secret별 교체 절차 표

A302 RB-08은 secret마다 교체 절차, 영향 범위, 되돌리기를 적었다(DB 비밀번호, Redis, 웹훅,
Grafana admin, 백업 age 키, SSH 키 등). 운영 secret을 실제로 바꿔 본 적은 없다고 적었다.

이 레포는 SOPS로 값 보관은 해결했지만, 바꿀 때 무엇을 다시 해야 하는지는 정리돼 있지 않다.
예를 들어 `POSTGRES_PASSWORD`는 빈 볼륨에서 처음 뜰 때만 적용되므로, SOPS 값만 바꾸고 배포하면
DB의 실제 비밀번호와 어긋난다. `ALTER ROLE`이 먼저다. 4번 스크립트가 생기면 비밀번호를 env 값으로
다시 맞추므로 이 문제는 줄어든다. SOPS 키 교체는 [ADR 0010](/adr/0010-sops-secrets.md)에 두 곳을
함께 바꾼다고 적혀 있다.

## 18. 설정이 바뀐 배포에서만 nginx 재생성

A302는 배포·롤백 순간에 연결이 한두 번 끊기는 것을 재고(RB-02 F절, 수백 건 중 1~2건) 감수하기로
했고, HSTS를 켤 때 Caddy를 재생성하자 외부 점검기로 약 2~3초 끊김을 쟀다(RB-05, 282번 중 연결
거부 1번).

이 레포 `scripts/deploy.sh`는 매 배포마다 nginx를 `--force-recreate`한다. template이 bind mount라
내용만 바뀌면 compose가 재생성하지 않기 때문이다. 그래서 nginx 설정과 무관한 배포에서도 모든
서브도메인이 잠깐 끊긴다. 관측 스택은 이미 설정 checksum을 환경변수로 넘겨 바뀐 서비스만
재생성한다. nginx에도 같은 방식(`nginx/` checksum)을 쓰면 끊김이 설정이 바뀐 배포로 줄어든다.
끊김 길이는 재지 않았다. 적용 전에 배포 중 외부에서 반복 요청을 보내 잰다.

# CI/CD 후보 (19~26)

A302는 GitLab이고 이 레포는 Jenkins라 문법은 다르지만, 파이프라인이 지키는 규칙은 옮길 수 있다.
비교 대상은 이 레포의 `Jenkinsfile`(`vps-infra-pipeline`, main만 빌드하는 단일 job)과
vps-info의 `Jenkinsfile`(multibranch, [ADR 0014](/adr/0014-multibranch-pr-ci.md))이다.

A302 파이프라인의 뼈대:

```txt
MR       -> verify(lint, 시험)                                   -> 병합 조건
develop  -> verify -> build:images(be:<sha>) -> deploy:dev  -> smoke:dev
master   -> verify -> build:images(같은 이미지) -> deploy:prod(사람이 누른다) -> smoke:prod
```

- 앞 단계가 성공해야 다음 단계가 돈다(`needs`).
- MR 코드는 서버 비밀이 없는 B의 러너에서, 배포는 보호된 브랜치만 받는 A의 러너에서 돈다.
- 배포 스크립트는 CI 없이도 서버에서 그대로 돌고(`deploy.sh <env> <sha>`), 사전 점검·잠금·
  사전 덤프·확인·실패 시 되돌리기를 스크립트가 맡는다. CI는 부르기만 한다.

마지막 원칙은 이 레포의 `Jenkinsfile` 첫 줄 주석("오케스트레이션만 담는다")과 같다. 아래 후보도
가능하면 Groovy가 아니라 `scripts/`에 넣는다.

## 19. 검증을 통과한 커밋만 배포

A302는 배포 잡이 verify 잡의 성공을 `needs`로 기다린다. 검증이 실패한 커밋은 배포 단계가
만들어지지 않는다.

이 레포는 같은 main push에 GitHub Actions `validate.yml`과 Jenkins `vps-infra-pipeline`이 따로
돈다. Jenkins는 Actions 결과를 보지 않고, main에는 브랜치 보호가 없다(2026-11-17 `gh api`로 확인).
그래서 Actions가 실패해도 배포는 나간다.

실제 위험은 이름보다 작다. `deploy.sh`가 적용 전에 `nginx -t`와 `docker compose config`를
직접 돌려, 그 두 가지 문법 오류는 배포 안에서 막힌다. 막히지 않는 것은 Actions에만 있는 검사다:
`test-select-target.sh`(배포 대상 판정), SOPS roundtrip, `check-sops.sh`, nginx local/live 렌더링.

적용 방법 후보:

- **Jenkins에 Verify stage를 둔다(추천).** Checkout 다음에 Actions와 같은 스크립트를 부른다.
  스크립트가 이미 `scripts/`에 있어 Jenkinsfile에 몇 줄이면 된다. Actions는 PR 검사로 남긴다.
- vps-info처럼 multibranch로 바꾸고 main 브랜치 보호로 Actions check를 필수로 둔다. 혼자 쓰는
  레포에 PR을 강제하게 되므로 무겁다.

## 20. 마이그레이션 전 덤프 (vps-info)

A302 `deploy.sh`는 prod에서 마이그레이션 파일이 바뀌었으면 사전 덤프를 먼저 뜨고, 일회성 컨테이너로
마이그레이션한다. 둘 중 하나라도 실패하면 트래픽을 건드리기 전에 멈춘다. 마이그레이션은 되돌리지
않는다(forward-fix). 사전 덤프는 잘못된 마이그레이션에서 돌아갈 유일한 지점이다.

vps-info는 compose의 `migrate` 서비스가 drizzle 마이그레이션을 돌린 뒤 app이 뜬다. migrate가
실패하면 app은 교체되지 않지만, 성공한 잘못된 마이그레이션은 되돌릴 덤프가 없다. vps-info
Jenkinsfile의 ERD stage가 이미 `changeset 'apps/backend/drizzle/**'` 조건을 쓰므로, 같은 조건으로
Deploy 앞에 `pg_dump -Fc` stage를 두면 된다. VPS의 한 디렉터리에 최근 몇 개만 남긴다.

같은 VPS에 두는 덤프라 VPS 소실은 막지 못한다. 그건 3번 몫이다. 3번이 생기면 사전 덤프도 같은
경로로 암호화해 올릴 수 있다(A302 `pg-backup.sh predeploy`).

## 21. SHA 태그 이미지와 직전 이미지 롤백

A302는 이미지를 `be:<sha>`, `fe:<sha>`로 만들고, 상태 파일에 `DEPLOYED_SHA`와 `PREVIOUS_SHA`를
적는다. `rollback.sh`는 다시 빌드하지 않고 직전 이미지로 컨테이너만 바꾼다. 이미지는 최근 5개를
남긴다(1번 prune과 짝). 운영 중 고친 함정: 같은 SHA를 다시 배포하면 직전 태그가 자기 자신으로
덮여 롤백 지점을 잃었다. 직전 릴리스 태그를 따로 적어 고쳤다(2026-10-27).

이 레포의 portal과 vps-info는 `docker compose up -d --build`로 빌드하고 `image:` 이름이 없어
매번 같은 이름(`latest`)을 덮어쓴다. 직전 이미지는 태그 없는 이미지로 밀려나 1번 prune이 생기면
지워진다. 되돌리려면 revert 커밋을 push해 다시 빌드해야 한다(수 분, 빌드 실패 가능).

적용 방법: compose에 `image: <이름>:${GIT_SHA}`를 두고 파이프라인이 SHA를 넘긴다. 롤백은 Jenkins
파라미터(예: `ROLLBACK_TO=<sha>`)로 빌드 없이 그 태그로 `up -d`한다. DB 마이그레이션은 되돌리지
않으므로 새 마이그레이션이 든 배포의 롤백은 이전 코드가 새 스키마에서 돌아야 한다.

## 22. 스모크가 배포된 SHA를 확인

A302 `smoke.sh --sha`는 엣지를 거쳐 `/api/v1/version`을 불러, 응답 SHA가 방금 배포한 SHA인지 본다.
200만 보면 옛 컨테이너가 계속 응답하는 경우(재생성 안 됨, 엣지가 다른 곳을 가리킴)를 통과시킨다.

이 레포 `healthcheck.sh`는 응답 코드만 보고, vps-info는 `--wait`로 컨테이너 healthcheck만 본다.
빌드 인자로 SHA를 이미지에 넣고 portal과 vps-info가 버전 경로나 응답 헤더로 내게 한 뒤,
healthcheck가 `DEPLOY_SHA`와 비교한다. 21번을 하면 SHA를 넘기는 길이 이미 생긴다.

## 23. PR 빌드만 이전 빌드 취소

A302는 `interruptible`을 verify 잡에만 둔다. 새 push가 오면 낡은 검증은 취소하지만, 배포 잡은
전환 도중에 끊기면 안 되므로 취소하지 않는다.

vps-info는 모든 브랜치가 `disableConcurrentBuilds()`라 PR에 연달아 push하면 낡은 Test가 줄을 서서
VPS CPU를 쓴다([ADR 0006](/adr/0006-jenkins-builds-on-vps.md)). PR 브랜치만
`disableConcurrentBuilds(abortPrevious: true)`로 두고 main은 지금처럼 기다리게 한다.
declarative `options`에서 브랜치별로 다르게 줄 수 있는지는 확인이 필요하다. 안 되면 job-dsl 쪽
설정이나 스크립트 `properties()`로 준다.

## 24. Jenkinsfile 구조 시험

A302 `test_pipeline_structure.py`는 `.gitlab-ci.yml`을 읽어 "배포 잡은 보호된 러너에서만",
"prod는 사람이 눌러야", "배포 잡은 전체 이력을 받는다", "verify 잡만 취소 가능" 같은 규칙을 시험한다.
규칙을 깨는 CI 변경은 MR에서 막힌다.

이 레포에서 같은 종류의 함정은 [ADR 0014](/adr/0014-multibranch-pr-ci.md)에 이미 적혀 있다:
단일 job에서는 `BRANCH_NAME`이 비어 `when { branch 'main' }`이 늘 거짓이고, 배포 stage를 건너뛰고도
빌드는 성공으로 보인다. 시험 후보:

- vps-info: `withCredentials`나 `docker compose up`이 있는 stage에는 `when { branch 'main' }`이 있다.
- `jobs.groovy`: multibranch의 fork PR 발견이 꺼져 있다.

Groovy를 파싱하지 않고 grep 수준으로 충분하다. 같은 레포의 PR이 시험까지 고칠 수 있으므로 사고
방지용이지 보안 경계가 아니다.

## 25. 빌드 베이스 이미지 버전 고정

A302는 CI 도구 이미지와 Dockerfile 베이스를 모두 패치 버전까지 고정하고, 같은 값이 두 곳에 있으면
일치하는지 시험한다.

이 레포 compose의 운영 이미지는 이미 패치 버전까지 고정돼 있다. 고정되지 않은 것은 빌드 쪽이다:
`portal/Dockerfile`의 `node:22-alpine`, `golang:1.22-alpine`, `alpine:3.20`, vps-info ERD stage의
`node:22-slim`. VPS에서 빌드하므로 코드가 같아도 베이스 태그가 움직이면 결과가 바뀐다.
태그를 패치 버전까지 적는다. 동기화 시험은 같은 값이 두 곳에 생길 때 더한다.

## 26. 배포 잠금과 이력

A302 `deploy.sh`는 환경별 잠금을 스크립트 안에서 잡아 CI와 사람이 동시에 배포하지 못하게 하고,
`history-<환경>.log`에 배포마다 한 줄을 남긴다. CI 밖에서 직접 배포하려면 `SKIP_VERIFY=<사유>`가
필요하고 사유가 이력에 남는다.

이 레포는 Jenkins의 `disableConcurrentBuilds()`가 같은 job 안에서만 막는다. SSH로 `deploy.sh`를
직접 돌리면 Jenkins 배포와 겹칠 수 있고, 그 배포는 Jenkins 빌드 기록에도 남지 않는다.
`deploy.sh`에 `flock`과 `.deploy-state/history.log` 한 줄(시각, SHA, 대상, Jenkins인지 수동인지,
결과)을 더한다. 혼자 운영해 겹칠 일이 드물어 우선순위는 낮다.

# 검사 원칙

A302 `preflight.sh`는 계약 문서를 읽지 못해 필수 키 목록이 비었을 때 검사가 통과하던
문제를 고쳐, 빈 목록을 실패로 본다. 위 검사를 만들 때도 검사 대상이 0개면 통과가 아니라
실패로 둔다. 예를 들어 포트 검사가 `compose config`를 읽지 못해 서비스 0개를 봤다면 실패다.

검사의 전제가 깨졌으면 채우고, 못 채우면 거부한다. A302 러너의 checkout이 얕은 저장소로 남아
merge-base 다운그레이드 가드가 정상 배포를 막자(2026-10-27), preflight가 `--unshallow`로 이력을
채우고 그래도 얕으면 거부하게 고쳤다. 이 레포의 `scripts/select-target.sh`는 이미 이 원칙을
따른다. `git diff`가 실패하거나 비면 판정 불가로 멈추고 대상을 사람이 넘기게 한다. 새 검사도
같은 방식으로 만든다.

# 가져오지 않는 것

| 항목 | 이유 |
|---|---|
| Blue/Green 배포, `rollback.sh` | 서버 2대와 무중단 요구가 전제다. 이 레포는 [누적 변경 배포](/spec/0002-infra-review-remediation.md)로 충분하다 |
| Caddy 엣지 | nginx와 certbot이 같은 역할을 한다 |
| `fit-up.sh` | [ADR 0003](/adr/0003-docker-restart-recovery.md)의 restart policy가 재부팅 복구를 한다 |
| GitLab Runner 2대, 이미지 아키텍처 검사 | 서버 1대, 아키텍처 1종이다 |
| 마이그레이션 불변 검사, 병합 커밋 금지 | 팀 작업용 규칙이다 |
| 서버에만 두는 env 파일, `envset.py` | SOPS가 로컬·CI·VPS를 한 파일로 맞춰 더 낫다 |
| 하루 두 번 상태 요약(`daily-digest.py`) | 백업과 외부 감시가 먼저 있어야 요약할 내용이 생긴다. 나중 후보다 |
| 알림 묶음·라우팅 정책 | A302는 알림이 35개라 필요하다. 이 레포는 4개다 |
| 경로별 CI job, 파이프라인 구조 시험, FE 번들 검사, 러너 동시 실행 조정 | 팀 작업, GitLab, Next.js 빌드가 전제다 |
| postgres_exporter용 `fit_monitor` role | DB 지표를 모으지 않는다. 모으게 되면 4번에 함께 넣는다 |
| 공통 CSP | 서브도메인마다 앱이 달라 허용 목록 하나로 맞출 수 없다(13번) |
| 서비스 종료 절차(RB-10: 최종 백업, 합성 덤프, 실데이터 삭제) | 종료 일정이 있는 서비스용이다. 이 VPS의 프로젝트를 내릴 때 다시 본다 |
| 팀원용 prod 읽기 전용 계정 | 혼자 운영한다 |
| AI API, Modal 예산·폴백 알림, CPU 크레딧 런북 | 해당 구성요소가 없다 |
| 세션 쿠키·CSRF 정책 | 인프라가 아니라 앱의 결정이다 |
| prod 수동 승인 게이트, dev→prod 이미지 승격 | 환경이 하나다 |
| CD 켜고 끄는 변수(`FIT_CD_ENABLED`) | Jenkins job 비활성화로 같은 일을 한다 |
| verify 러너와 deploy 러너 분리 | 서버가 1대다. 다만 A302가 분리한 이유(MR 코드가 서버 비밀과 docker 권한에 닿지 않게)는 이 레포에도 있다. vps-info PR 빌드는 PR 브랜치의 Jenkinsfile을 그대로 쓰므로 `when` 조건을 지운 PR도 credential에 닿는다. 지금은 혼자 push해서 괜찮지만 협업자가 생기면 PR 빌드를 secret 없는 agent로 옮긴다 |
| 경로별 잡, CI 캐시 정책, FE 시험 범위 축소 | 빌드가 작아 시간 절약이 크지 않다 |
| 배포 실패 경로 시험(`test/test-deploy.sh`, 목 이미지) | 가치는 있지만 21번 롤백이 생긴 뒤에 볼 것이다 |

# 확정 전에 확인할 것

- VPS의 `docker system df` 결과와 Docker 데몬 로그 설정
- `signal_archive` 크기(`pg_database_size`)와 R2 무료 용량 대비 보관 기간
- R2 버킷 잠금 지원 여부와 토큰 권한 범위
- 1번과 3번을 호스트 timer로 할지 Jenkins 주기 job으로 할지
- 10번 외부 서비스의 무료 한도와 Mattermost 연동 여부
- 14번: Hostinger VPS의 컨테이너에서 `169.254.169.254`가 응답하는지
- 15번: Prometheus의 cAdvisor job 이름과 `container_last_seen`의 `name` label 값
- 16번: SOPS age 개인키의 현재 사본 위치
- 19번: Verify stage로 할지 multibranch·브랜치 보호로 할지
- 23번: declarative `options`에서 브랜치별 `abortPrevious`를 줄 수 있는지

# 관련 개념

- [Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
- [PostgreSQL](/services/postgresql.md)
- [관측 스택](/services/observability.md)
- [nginx 리버스 프록시](/services/nginx.md)
- [장애 진단](/runbooks/failure-diagnosis.md)
