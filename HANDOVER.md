# 인수 지침서 — 로컬 우선 인프라 재구성

2026-08-24 작업 결과. **무엇을 했고, 그것이 코드 어디에 있는지**를 정리한다.

기준: `312ddcd`(작업 전) → `d387730`(현재). 커밋 15개, 85개 파일.
설계 근거는 [spec 0001](okf/spec/0001-local-first-infra.md)과
[ADR 0006~0010](okf/adr/index.md)에 있다.

---

## 1. 지금 무엇이 달라졌나 (한 문단)

배포 로직·라우팅·secret·Jenkins 설정을 **로컬에서 먼저 검증하고 환경변수 교체만으로
VPS에 적용**하는 구조로 바꿨다. VPS는 이미 새 구조로 전환되어 동작 중이며
(`~/app/vps-infra`, nginx 템플릿, JCasC Jenkins), 옛 경로(`/opt/*`)는 롤백용으로
남겨두었다.

## 2. 코드 지도 — 어디를 보면 되나

### 배포 로직 (seam 1)

| 파일 | 역할 |
|------|------|
| [`scripts/select-target.sh`](scripts/select-target.sh) | **배포 대상 판정.** git 리비전 2개 → `portal`\|`all`. 부수효과 없음 |
| [`scripts/deploy.sh`](scripts/deploy.sh) | 대상 문자열을 받아 compose 적용 |
| [`scripts/healthcheck.sh`](scripts/healthcheck.sh) | 도메인·스킴을 환경변수로 받음 |
| [`Jenkinsfile`](Jenkinsfile) | **오케스트레이션만.** 판정 Groovy 코드 없음 |
| [`scripts/test-select-target.sh`](scripts/test-select-target.sh) | seam 1 검증 6개 |

**가장 먼저 볼 것**: `select-target.sh`의 주석. **빈 diff는 `exit 1`(판정 불가)**
이며, 이유가 거기 적혀 있다. 기존 Jenkinsfile은 `files.every{}`가 빈 리스트에서
`true`가 되어 `portal`로 판정했는데, 그건 "판정 실패"를 "portal만 변경"으로
해석해 인프라 변경을 조용히 누락시킨다. 의도적 배포는 `DEPLOY_TARGET`
파라미터로 override한다.

### nginx 라우팅 (seam 2)

| 파일 | 역할 |
|------|------|
| [`nginx/templates/*.conf.template`](nginx/templates/) | 서비스 1개 = 템플릿 1개. `${BASE_DOMAIN}` 등을 nginx 이미지 entrypoint가 `envsubst`로 치환 |
| [`nginx/tls/none.conf`](nginx/tls/none.conf) / [`live.conf`](nginx/tls/live.conf) | TLS 지시자를 모드별로 분리. `none`은 빈 파일이라 로컬이 인증서 없이 기동됨 |
| [`nginx/tls/none-challenge.conf`](nginx/tls/none-challenge.conf) / [`live-challenge.conf`](nginx/tls/live-challenge.conf) | 80번 challenge/리다이렉트도 모드별 분리 |
| [`scripts/test-routing.sh`](scripts/test-routing.sh) | seam 2 검증. HTTP(로컬)·HTTPS(VPS) 양쪽 지원 |

환경변수 계약:

| 변수 | 로컬 | VPS |
|------|------|-----|
| `BASE_DOMAIN` | `localhost` | `kkh-hub.tech` |
| `NGINX_LISTEN` | `80` | `"443 ssl"` (따옴표 필수) |
| `TLS_MODE` | `none` | `live` |
| `CHALLENGE_DOMAINS` | 더미 | 5개 도메인 |

**주의 두 가지가 템플릿 주석에 적혀 있다.**
`jenkins.conf.template`은 upstream을 변수+`resolver`로 쓴다 — 이름을 직접 쓰면
Jenkins가 없는 로컬에서 nginx 전체가 기동에 실패한다.
`00-http-challenge.conf.template`의 `CHALLENGE_DOMAINS`에 새 도메인을 빼먹으면
인증서 발급이 실패한다(의도적으로 유지된 함정).

### secret (seam 3)

| 파일 | 역할 |
|------|------|
| [`.sops.yaml`](.sops.yaml) | 암호화 규칙. **주석을 꼭 읽을 것** — 규칙은 암호화 때만 적용되고 복호화는 확장자로 판단한다 |
| [`scripts/secrets.sh`](scripts/secrets.sh) | `decrypt` / `encrypt` / `edit`. `ENV_NAME`으로 환경 선택 |
| [`scripts/check-sops.sh`](scripts/check-sops.sh) | 평문 커밋 탐지. key 없이 동작하므로 CI에서 사용 |
| `secrets/env.local.sops.env` | 로컬 값 |
| `secrets/env.prod.sops.env` | **VPS 운영 값** |
| `secrets/notes.htpasswd.sops.txt` | notes Basic Auth |
| `secrets/github-pat.sops.txt` | Jenkins checkout용 PAT |

복호화 명령(둘 다 필요):

```bash
# 로컬
HOST_UID=$(id -u) HOST_GID=$(id -g) \
  docker compose run --rm tools ./scripts/secrets.sh decrypt

# VPS
ENV_NAME=prod HOST_UID=$(id -u) HOST_GID=$(id -g) \
  docker compose run --rm tools ./scripts/secrets.sh decrypt
```

`HOST_UID`/`HOST_GID`가 없으면 결과가 `root:root 600`이 되어 compose가 `.env`를
읽지 못한다(tools 컨테이너가 root로 동작하기 때문).

### Jenkins 설정 (코드로 관리)

| 파일 | 역할 |
|------|------|
| [`jenkins/plugins.txt`](jenkins/plugins.txt) | **최상위 11개만** 버전 고정. 하위 의존성은 CLI가 자동 해석(실제 설치 83개) |
| [`jenkins/jenkins.yaml`](jenkins/jenkins.yaml) | JCasC. anonymous read 차단, signup 차단, credential 2개, job-dsl seed |
| [`jenkins/jobs.groovy`](jenkins/jobs.groovy) | Job 정의. SCM URL을 환경변수로 받아 로컬/VPS 겸용 |
| [`jenkins/compose.yml`](jenkins/compose.yml) | `mem_limit` + JVM heap 상한. Jenkins만 적용 |

**⚠️ GUI에서 바꾼 설정은 재기동 시 사라진다.** JCasC가 덮어쓴다.
설정 변경은 `jenkins.yaml` 수정 → 커밋 → 재배포.

### 도구·CI

| 파일 | 역할 |
|------|------|
| [`tools/Dockerfile`](tools/Dockerfile) | 스크립트 실행 진입점. 호스트 셸(PowerShell/zsh) 무관 |
| [`.github/workflows/validate.yml`](.github/workflows/validate.yml) | **검증 전용.** 배포 workflow는 삭제됨 |
| [`.gitattributes`](.gitattributes) | `*.sh`를 LF로 고정 (CRLF면 컨테이너에서 실패) |

---

## 3. VPS 현재 상태

| 항목 | 값 |
|------|-----|
| 배포 경로 | `~/app/vps-infra` (sudo 불필요) |
| 옛 경로 | `/opt/vps-infra`, `/opt/quartz-site` — **롤백용 보존** |
| nginx | 템플릿 구조, 운영 인증서 (만료 2026-11-07) |
| Jenkins | 2.568.2, JCasC 관리, Job 자동 생성 |
| notes 콘텐츠 | `vps_quartz_site` named volume (68개 파일) |
| age key | `~/.config/sops/age/keys.txt` (mode 600) |

검증값: portal/health/apex **200**, notes **401**, jenkins **403**

### 백업 위치

`~/backups/stage6-20260824/` — 전부 복원 가능성 검증됨

```txt
jenkins_data.tar.gz              525M  최초 백업
jenkins_data_pre-jcasc.tar.gz    525M  JCasC 전환 직전
certbot_etc.tar.gz                     인증서
postgres_all.sql.gz                    DB 논리 백업
env.vps.backup                         전환 전 .env (평문)
notes.htpasswd.backup                  전환 전 htpasswd
```

옛 Jenkins volume은 `vps_jenkins_data_pre_jcasc` 볼륨으로도 보존됨.

### 롤백

```bash
# 인프라
cd ~/app/vps-infra && docker compose down
cd /opt/vps-infra && docker compose up -d

# Jenkins (옛 volume으로)
docker volume rm vps_jenkins_data
docker volume create vps_jenkins_data
docker run --rm -v vps_jenkins_data_pre_jcasc:/from:ro -v vps_jenkins_data:/to \
  alpine:3.24 sh -c 'cp -a /from/. /to/'
cd /opt/vps-infra/jenkins && docker compose --env-file /opt/jenkins/.env up -d
```

---

## 4. 검증 방법

### 빠른 루프 (수초)

```bash
./scripts/test-select-target.sh
docker compose run --rm --no-deps tools ./scripts/test-sops.sh
./scripts/check-sops.sh
```

### 느린 루프 (수분)

```bash
docker compose up -d --build
./scripts/test-routing.sh          # 로컬 HTTP
./scripts/healthcheck.sh
```

VPS에서:

```bash
cd ~/app/vps-infra
BASE_URL=https://kkh-hub.tech BASE_DOMAIN=kkh-hub.tech \
  NOTES_USER=<사용자> NOTES_PASS=<비밀번호> ./scripts/test-routing.sh
```

---

## 5. 이번 작업에서 잡은 실제 버그 12개

로컬 검증만으로는 드러나지 않았고, 그대로 두면 배포가 깨졌을 것들이다.
각 항목에 회귀 방지를 넣었다.

| # | 문제 | 커밋 |
|---|------|------|
| 1 | nginx가 `jenkins` upstream 미해석 시 기동 거부 → Jenkins 없는 로컬에서 nginx 전체 사망 | `88861f5` |
| 2 | `CHALLENGE_DOMAINS=localhost`가 `portal.localhost`와 충돌 | `88861f5` |
| 3 | Jenkinsfile `environment` 블록의 자기참조로 `APP_DIR`이 `/opt/vps-infra`로 떨어짐 | `2620165` |
| 4 | `dir()`의 `@tmp` 형제 디렉터리 → 부모가 Jenkins 소유 아니면 AccessDenied | `4feba8b` |
| 5 | `APP_DIR` ≠ `APP_DIR_HOST` → `not a directory` (docker.sock 제약) | `4feba8b` |
| 6 | Jenkins가 로컬 경로 checkout을 기본 거부 → 미push 커밋 테스트 불가 | `2620165` |
| 7 | CI nginx 검증이 항상 실패 (`nginx -t`가 upstream을 DNS 해석) | `d0a73ff` |
| 8 | **clean clone에서 `up`이 실패** — 없는 htpasswd 경로에 Docker가 디렉터리 생성 | `5159e21` |
| 9 | `.sops` 확장자로는 복호화 불가 — 규칙은 암호화 때만 적용됨 | `59cc877` |
| 10 | `ENV_NAME`이 컨테이너에 전달 안 됨 → VPS에 로컬 설정 배포될 상황 | `0e8ea40` |
| 11 | `NGINX_LISTEN=443 ssl` 공백 미인용 → `ssl: command not found` | `d96f4fb` |
| 12 | **htpasswd 600 + nginx 워커 비-root → notes가 500** (Linux 전용, macOS는 재현 안 됨) | `e52abdb` |

---

## 6. 남은 작업

### 보안 (우선)

1. **age key 교체 권장.** 작업 중 대화에 개인키가 노출됐다.
   ```bash
   age-keygen -o ~/.config/sops/age/keys.new
   # .sops.yaml의 age: 를 새 공개키로 교체 후 모든 secret 재암호화
   ```
2. **운영 DB 비밀번호 교체 권장.** 같은 이유로 평문이 노출됐다.
3. **GitHub PAT 폐기·재발급 권장.** 같은 이유. classic `repo` scope는 전체 repo에
   읽기·쓰기 권한을 준다.
4. **레포 private 전환 검토.** 현재 public이라 암호화 secret이 공개 노출된다.
   SOPS 암호화는 유효하지만 age key가 유일한 보호 수단이 된다.

### 기능 (spec 단계 7~8)

| 단계 | 내용 | 선행 조건 |
|------|------|-----------|
| 7 | Quartz 이미지화 | `quartz-site-private` 레포 수정. **현재 `QUARTZ_SCM_URL`을 설정하면 Job은 생기지만 빌드는 실패한다** — 옛 구조가 의존한 `/opt/quartz-*` 마운트를 제거했기 때문 |
| 8 | 신규 프로젝트 추가 | 대상 미정 |

### 문서 정합성

`README.md`, `INFRA.md`, `OBSERVABILITY.md`는 여전히 `/opt/vps-infra`와
`nginx/conf.d/`를 서술한다. **이제 실제와 다르다.** 안정화 후 갱신 필요.

---

## 7. 관련 문서

- [spec 0001 — 로컬 우선 인프라 재구성](okf/spec/0001-local-first-infra.md)
- [인수 절차 런북](okf/runbooks/local-first-handover.md) — 명령 위주
- [ADR 0006~0010](okf/adr/index.md) — 결정 근거
