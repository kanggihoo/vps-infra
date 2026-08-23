---
type: Runbook
title: 로컬 우선 인프라 인수 절차
description: spec 0001 단계 0~5 구현 후 사용자가 직접 해야 하는 작업과 로컬 검증 명령을 정리한다.
tags: [runbook, local-development, sops, jenkins, handover]
timestamp: 2026-08-23T00:00:00+09:00
---

# 이 문서의 범위

[spec 0001](/spec/0001-local-first-infra.md)의 **단계 0~5**가 구현된 상태에서,
사용자만 할 수 있는 작업(키 생성, 실제 secret 값)과 로컬 검증 명령을 정리한다.

단계 6~8(VPS 적용, Quartz 이미지화, 신규 프로젝트)은 미구현이다.

# 사용자 작업 (필수)

## 1. age key 생성과 `.sops.yaml` 채우기

`.sops.yaml`의 `REPLACE_WITH_YOUR_AGE_PUBLIC_KEY`가 placeholder다. 실제 키가
없으면 secret 관련 기능이 동작하지 않는다.

```bash
mkdir -p ~/.config/sops/age
docker compose run --rm --entrypoint age-keygen tools -o /root/.config/sops/age/keys.txt
```

호스트에 직접 설치했다면 `age-keygen -o ~/.config/sops/age/keys.txt`도 된다.
출력된 `Public key: age1...`을 `.sops.yaml`의 두 `age:` 항목에 넣는다.

**key를 분실하면 secret을 복호화할 수 없다.** 백업이 운영 요구사항이다
([ADR 0010](/adr/0010-sops-secrets.md)).

## 2. secret 암호화

현재 `.env`에는 traefik 잔재(`ACME_EMAIL`, `TRAEFIK_DASHBOARD_AUTH`)가 남아
있다. 암호화 전에 지운다. 이 파일은 gitignored이므로 구현 중 건드리지 않았다.

```bash
# .env
docker compose run --rm tools ./scripts/secrets.sh encrypt .env secrets/env.sops

# notes Basic Auth (사용자/비밀번호를 직접 정한다)
docker run --rm httpd:2.4-alpine htpasswd -nbB <user> <password> > /tmp/notes.htpasswd
docker compose run --rm tools ./scripts/secrets.sh encrypt /tmp/notes.htpasswd secrets/notes.htpasswd.sops
rm /tmp/notes.htpasswd

# GitHub PAT
docker compose run --rm tools ./scripts/secrets.sh encrypt <pat파일> secrets/github-pat.sops
```

암호화한 `secrets/*.sops`는 커밋한다. 복호화 결과(`.env`,
`secrets/notes.htpasswd`)는 gitignored다.

## 3. 로컬 `.env`와 `jenkins/.env` 준비

```bash
cp .env.example .env          # 또는 secrets.sh decrypt
cp jenkins/.env.example jenkins/.env
```

`.env.example`의 `NOTES_HTPASSWD`는 공개 테스트 fixture(`test`/`test`)를
가리킨다. clean clone에서도 `docker compose up`이 성공하도록 한 기본값이다.
실제 secret으로 바꿀 때만 수정한다.

```bash
NOTES_HTPASSWD=./secrets/notes.htpasswd
```

`jenkins/.env`에서 **반드시** 수정할 항목:

| 변수 | 값 |
|------|-----|
| `APP_DIR`, `APP_DIR_HOST` | 둘 다 이 레포의 절대 경로 (같아야 한다) |
| `INFRA_SCM_URL` | 같은 절대 경로 |
| `ALLOW_LOCAL_CHECKOUT` | `true` |
| `UPDATE_APP_DIR` | 편집 중인 레포면 `false` |
| `JENKINS_ADMIN_PASSWORD` | 직접 정한다 |
| `DOCKER_GID` | Linux는 `getent group docker \| cut -d: -f3`, macOS는 `0` |

`APP_DIR`과 `APP_DIR_HOST`가 다르면 배포가 `not a directory`로 실패한다.
Jenkins가 `docker.sock`으로 실행하는 compose의 bind mount 경로는 호스트
기준으로 해석되기 때문이다.

# 로컬 검증 명령

## 빠른 루프 (수초)

```bash
# seam 1 — 배포 대상 판정
./scripts/test-select-target.sh

# seam 3 — SOPS 왕복
docker compose run --rm --no-deps tools ./scripts/test-sops.sh
```

## 느린 루프 (수분)

```bash
# 스택 기동
docker compose up -d --build

# seam 2 — 라우팅, try_files, Basic Auth, TLS 모드 분기
./scripts/test-routing.sh

# 헬스체크
./scripts/healthcheck.sh
```

브라우저로 `http://portal.localhost`에 접속한다. `*.localhost`는 브라우저가
`127.0.0.1`로 풀어주므로 hosts 파일 수정이 필요 없다.

## 로컬 Jenkins

```bash
cd jenkins && docker compose --env-file .env up -d --build
```

`http://localhost:8080`에서 `vps-infra-pipeline` Job이 **자동 생성**되어 있다.
`DEPLOY_TARGET`을 골라 빌드한다.

- `auto` — 스크립트가 판정한다. 판정 불가면 실패한다.
- `all` / `portal` — 판정을 건너뛴다.

## 정리

```bash
docker compose down -v          # DB까지 삭제
cd jenkins && docker compose down -v
```

# 알아야 할 제약

- **GUI에서 바꾼 Jenkins 설정은 재기동 시 사라진다.** JCasC가 기동 시
  덮어쓴다. 설정 변경은 `jenkins/jenkins.yaml` 수정 → 커밋 → 재배포로 한다
  ([ADR 0009](/adr/0009-jenkins-config-as-code.md)).
- **빈 diff는 배포하지 않고 실패한다.** 판정 불가를 "portal만 변경"으로
  해석하면 인프라 변경이 조용히 누락되기 때문이다. 의도적 배포는
  `DEPLOY_TARGET`으로 override한다.
- **로컬은 HTTP만 쓴다.** TLS는 VPS에서만 검증한다. 단 CI가 VPS 모드
  템플릿의 문법과 인증서 경로를 검증한다.
- **새 서브도메인을 추가하면** 템플릿 1개와 `.env`의 `CHALLENGE_DOMAINS`를
  수정한다. 후자를 빼면 인증서 발급이 실패한다.

# 미구현 (단계 6~8)

| 단계 | 내용 | 막힌 이유 |
|------|------|-----------|
| 6 | VPS 적용 (`app/` 이전, JCasC 전환) | VPS SSH 접근과 Jenkins volume 백업 필요 |
| 7 | Quartz 이미지화 | `quartz-site-private` 레포 수정 필요 |
| 8 | 신규 프로젝트 추가 | 대상 프로젝트 미정 |

단계 6 착수 전 Jenkins volume을 백업한다. VPS에 plugin 94개와 GUI Job 2개가
있어 JCasC 전환 시 충돌할 수 있다(spec 알려진 리스크 1).

## 문서 정합성

`README.md`, `INFRA.md`, `OBSERVABILITY.md`는 여전히 `/opt/vps-infra`,
`/opt/quartz-site`, `nginx/conf.d/`를 서술한다. 이는 **현재 VPS의 실제 상태**가
맞으므로 지금 고치지 않았다. 단계 6에서 VPS를 `app/`과 템플릿 구조로 전환할 때
함께 갱신한다. 레포와 VPS가 갈라져 있는 이 기간에는 두 문서가 서로 다른 시점을
서술한다는 점을 알고 읽어야 한다.

# 관련 개념

- [로컬 우선 인프라 재구성](/spec/0001-local-first-infra.md)
- [nginx 설정의 환경 템플릿화](/adr/0008-nginx-env-templates.md)
- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
