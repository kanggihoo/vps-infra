---
type: Deployment Service
title: Jenkins 배포
description: VPS 내부 Docker Jenkins가 GitHub webhook을 받아 인프라를 배포한다.
tags: [deployment, jenkins, docker, webhook]
timestamp: 2026-09-29T00:00:00+09:00
---

# 개요

Jenkins는 기존 인프라 Compose project와 분리된 Docker Compose project로
실행한다. nginx 뒤 `jenkins.kkh-hub.tech`로 접근하며, GitHub webhook이
Pipeline을 시작한다.

이번 단계에서는 GHCR를 사용하지 않는다. Jenkins가 사용자 홈 아래 `app/vps-infra`에서
repository를 checkout하고, VPS Docker daemon에서 portal 이미지를 build한 뒤
기존 `scripts/deploy.sh`를 실행한다.

# 흐름

```txt
GitHub push (vps-info는 pull_request도, ADR 0014)
-> GitHub webhook
-> Jenkins container
-> ~/app/vps-infra checkout
-> SOPS 복호화 (sops-age-key credential, ENV_NAME=prod -> .env, secret 파일)
-> docker compose config
-> scripts/deploy.sh
-> scripts/healthcheck.sh
```

Pipeline은 checkout 갱신 직후 SHA를 이번 배포 SHA로 고정한다. `.deploy-state/last-successful-sha`
부터 그 SHA까지의 누적 변경으로 `portal` 또는 `all` 대상을 고른다. healthcheck가 성공한
경우에만 상태 SHA를 갱신한다. 이 상태 파일은 VPS checkout의 runtime state라 Git에 커밋하지
않는다. 파일이 없거나 Git history가 이어지지 않으면 안전하게 전체 배포한다.

Jenkins가 Docker socket을 사용하므로 host Docker daemon에 높은 권한을 가진다.
Jenkins 관리자와 Pipeline 수정 권한을 제한하고, public 접근은 nginx HTTPS와
Jenkins 인증 뒤에 둔다.

VPS의 `.env`는 매 배포마다 `secrets/env.prod.sops.env`에서 다시 만들어진다. VPS에서 `.env`를
직접 고치면 다음 배포에서 덮어써지므로 값은 항상 SOPS 파일에서 바꾼다.

# 초기화

Jenkins 설치는 관리자 SSH 또는 VPS console에서 `kkh` 사용자로 1회 수행한다.
`sudo`는 필요 없다.

```bash
git clone https://github.com/kanggihoo/vps-infra.git ~/app/vps-infra
cd ~/app/vps-infra/jenkins
cp .env.example .env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" .env
# 관리자 비밀번호, PAT, 경로, age key(base64 한 줄)를 채운다.
docker compose --env-file .env up -d --build
```

Jenkins 자신의 설정 파일은 `~/app/vps-infra/jenkins/.env`다. Git에 커밋되지 않으며
SOPS 관리 대상도 아니다. `/opt/jenkins/.env`는 옛 경로이며 더 이상 쓰지 않는다.

# age key 위치

VPS에는 같은 age key가 두 형태로 있다(2026-09-29 해시 비교로 확인).

| 위치 | 용도 |
|------|------|
| `~/app/vps-infra/jenkins/.env`의 `SOPS_AGE_KEY_CONTENT` | base64 한 줄. JCasC가 `sops-age-key` credential로 등록하고 파이프라인이 이것으로 복호화한다. |
| `~/.config/sops/age/keys.txt` | 원본. 관리자가 VPS에서 `sops`를 직접 실행할 때 쓴다. 파이프라인은 읽지 않는다. |

key를 교체하면 두 곳을 함께 바꾸고 Jenkins를 재기동한다.

# 자동화 범위

push 이후 checkout 갱신(`git pull`), 복호화, 서비스 배포, healthcheck는 Jenkins가
수행한다. 관리자가 수동 SSH로 서비스를 배포할 필요는 없다.

JCasC 설정(`jenkins/casc/`)은 컨테이너에 마운트되어 있다. 파이프라인은 마지막 단계에서
JCasC를 reload하므로 `jenkins.yaml` 수정과 Job 추가는 push만으로 반영된다
([ADR 0009](/adr/0009-jenkins-config-as-code.md)). reload는 Jenkins를 재시작하지 않는다.

Jenkins 컨테이너 자체는 파이프라인이 재생성하지 않는다(ADR 0007). `plugins.txt`,
`Dockerfile`, `compose.yml`, `jenkins/.env`를 바꾸면 VPS에서 다음을 직접 실행해야 반영된다.
이때 Jenkins가 잠깐 내려가며, 그 사이의 webhook은 유실될 수 있다.

```bash
cd ~/app/vps-infra/jenkins && docker compose --env-file .env up -d --build
```

# 빌드 알림

모든 job은 `post { always { notifyMattermost() } }`로 성공·실패를 SSAFY Mattermost 한 채널에 보낸다.
함수는 `jenkins/shared-lib/`에 있고 JCasC가 implicit 라이브러리 `vps-shared`로 등록한다. webhook URL은
`jenkins/.env`의 `MATTERMOST_WEBHOOK_URL`이며 비어 있으면 알림을 건너뛴다
([ADR 0012](/adr/0012-mattermost-build-notification.md)).

# 보안

- Jenkins를 기존 `compose.yml`에 넣지 않는다. 배포 중 Jenkins 재생성을 피한다.
- `8080`을 public port로 publish하지 않는다. nginx만 `80/443`을 노출한다.
- Jenkins GitHub credential과 administrator password를 repository에 저장하지 않는다.
- Jenkins의 anonymous read와 signup을 비활성화한다.
- `/var/run/docker.sock` mount는 host Docker 제어 권한을 의미한다.

# 관련 개념

- [시스템 아키텍처 개요](/architecture/system-overview.md)
- [GitHub Actions 배포](/services/github-actions-deploy.md)
- [초기 배포 검증](/runbooks/initial-deployment-validation.md)
