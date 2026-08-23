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

# 완료된 SOPS 설정

age key 생성과 secret 암호화는 **완료되었다.** 아래는 현재 상태다.

| 항목 | 상태 |
|------|------|
| age key | `~/.config/sops/age/keys.txt` (mode 600, 커밋 안 됨) |
| 공개키 | `.sops.yaml`에 반영됨 |
| `.env` (로컬) | `secrets/env.local.sops.env`로 암호화 |
| `.env` (VPS) | `secrets/env.prod.sops.env`로 암호화, 운영 DB 값 보존 |
| notes Basic Auth | `secrets/notes.htpasswd.sops.txt` (VPS 기존 자격증명 그대로) |
| `github-pat` | **미암호화.** PAT 발급이 필요하다(아래 참조) |

## ⚠️ age key 백업 (남은 필수 작업)

**key를 분실하면 secret을 복호화할 수 없다.** 백업이 운영 요구사항이다
([ADR 0010](/adr/0010-sops-secrets.md)). `~/.config/sops/age/keys.txt`를
비밀번호 관리자나 오프라인 매체에 보관한다.

VPS 적용(단계 6) 시 같은 파일을 VPS의 `~/.config/sops/age/keys.txt`에 두고,
Jenkins에는 `SOPS_AGE_KEY_CONTENT`로 주입한다.

## github-pat (단계 6 전까지 불필요)

로컬 Jenkins는 로컬 경로를 SCM으로 쓰므로 PAT가 필요 없다. VPS 적용 시
GitHub에서 PAT를 발급해 암호화한다.

```bash
printf '%s' '<PAT값>' > /tmp/pat
docker compose run --rm tools ./scripts/secrets.sh encrypt /tmp/pat secrets/github-pat.sops.txt
rm /tmp/pat
```

## secret 갱신 방법

환경별로 `.env` 한 벌씩 둔다. `ENV_NAME`으로 고른다(기본 `local`).

```bash
# 로컬 값으로 복호화
docker compose run --rm tools ./scripts/secrets.sh decrypt

# VPS 값으로 복호화
ENV_NAME=prod docker compose run --rm tools ./scripts/secrets.sh decrypt

# 값 수정 후 재암호화
docker compose run --rm tools ./scripts/secrets.sh encrypt .env secrets/env.local.sops.env
```

환경을 늘릴 때는 `secrets/env.<이름>.sops.env`를 추가하면 된다
(spec 사용자 스토리 14).

암호화 파일(`secrets/*.sops.*`)은 커밋한다. 복호화 결과(`.env`,
`secrets/notes.htpasswd`)는 gitignored다.

**파일명이 `.sops.env` / `.sops.txt`인 이유**: `creation_rules`는 암호화할
때만 적용되고, 복호화할 때 SOPS는 **확장자**로 형식을 판단한다. `.sops`로
끝내면 JSON으로 추측해 실패한다.

## `jenkins/.env` 준비 (남은 작업)

```bash
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
