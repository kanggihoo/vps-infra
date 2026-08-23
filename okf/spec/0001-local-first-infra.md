---
type: Spec
title: 로컬 우선 인프라 재구성
description: 배포 로직과 nginx 설정을 로컬에서 검증 가능하게 만들고, Jenkins 설정과 secret을 레포에서 관리한다.
tags: [infrastructure, local-development, jenkins, nginx, sops, spec]
timestamp: 2026-08-23T00:00:00+09:00
---

# 문제 정의

현재 인프라는 **로컬에서 실행하거나 검증할 수 없다.** 사용자 관점의 증상은 다음과 같다.

1. **배포 로직을 로컬에서 돌릴 수 없다.** 배포 대상 판정 로직이 Jenkinsfile 안 Groovy로
   작성되어 있어(`env.DEPLOY_TARGET`, `sh(returnStdout:)`) Jenkins 런타임 밖에서는
   실행 자체가 불가능하다. 판정에 버그가 있으면 Jenkins를 띄우고 Job을 만들고 커밋을
   push해야 확인된다.

2. **nginx 설정을 로컬에서 기동할 수 없다.** conf가 `listen 443 ssl`로 고정되어 인증서가
   없는 로컬에서는 nginx가 시작에 실패한다. `server_name`도 `*.kkh-hub.tech`로
   하드코딩되어 로컬 요청은 어느 server block에도 매칭되지 않는다.

3. **경로가 VPS 기준으로 하드코딩되어 있다.** `/opt/vps-infra`가 Jenkinsfile에 5회,
   `/opt/quartz-site`와 `/opt/nginx-auth`가 compose에 등장한다. 이 경로는 Mac이나
   Windows에 존재하지 않는다.

4. **root 소유 경로가 작업을 막는다.** `/opt/jenkins`와 `/opt/nginx-auth`가 root 소유여서
   `sudo` 없이는 다룰 수 없다.

5. **Jenkins 설정이 레포에 없다.** Job 2개(`quartz-deploy`, `vps-infra-pipeline`),
   plugin 94개, credential 1개가 VPS UI 수동 작업으로만 존재한다. volume이 유실되면
   전부 수작업 복구이며, 로컬에서 파이프라인을 테스트할 때마다 Job을 손으로 만들어야 한다.

6. **secret을 로컬에서 재현할 수 없다.** 평문 `.env`가 VPS에만 있고, Basic Auth 파일은
   root 소유 호스트 경로에 있다.

7. **Windows와 Mac을 번갈아 쓸 때 깨진다.** `.gitattributes`가 없어 `.sh` 파일이 CRLF로
   checkout되면 컨테이너 안에서 실행이 실패한다. 주 작업 환경이 PowerShell인데 배포
   스크립트는 bash다.

8. **이미지 태그가 고정되지 않았다.** `jenkins/jenkins:lts-jdk21`, `nginx:alpine`,
   `certbot/certbot`(= `latest`)는 움직이는 태그다. Dockerfile이 바뀌지 않았는데도
   빌드 시점에 따라 다른 이미지가 나온다.

# 해결 방향

배포 로직·라우팅·secret·Jenkins 설정을 **로컬에서 먼저 검증하고, 환경변수 교체만으로
VPS에 동일 적용**하는 구조로 바꾼다.

- 배포 로직을 Jenkinsfile에서 셸 스크립트로 내려 로컬 셸에서 즉시 실행 가능하게 한다.
- nginx conf를 `envsubst` 템플릿 한 벌로 만들어 도메인·포트·TLS 모드를 환경변수로 뺀다.
- 배포 경로를 홈 디렉터리 아래 `app/`으로 옮겨 `sudo` 의존을 없앤다.
- Jenkins 설정과 Job을 JCasC/job-dsl로 레포에서 관리한다.
- secret을 SOPS로 암호화해 레포에 커밋하고, 복호화 key만 각 환경에 둔다.
- 스크립트를 `tools` 컨테이너에서 실행해 호스트 셸 종류(PowerShell/zsh)와 무관하게 만든다.

근거가 되는 결정은 [ADR 0006~0010](/adr/index.md)에 기록되어 있다.

# 사용자 스토리

## 로컬 검증

1. 개발자로서, 배포 대상 판정 로직을 셸 한 줄로 실행하고 싶다. 그래야 Jenkins를 띄우지
   않고 판정 버그를 찾을 수 있다.
2. 개발자로서, 로컬에서 `docker compose up` 후 브라우저로 `portal.localhost`에
   접속하고 싶다. 그래야 라우팅이 맞는지 배포 전에 확인할 수 있다.
3. 개발자로서, 로컬 nginx가 인증서 없이 기동되기를 원한다. 그래야 TLS 설정 때문에
   로컬 검증이 막히지 않는다.
4. 개발자로서, 서비스 이름이나 포트를 잘못 적었을 때 로컬에서 502를 보고 싶다.
   그래야 배포 후에 발견하지 않는다.
5. 개발자로서, 로컬에서 hosts 파일을 수정하지 않고 서브도메인에 접속하고 싶다.
6. 개발자로서, 로컬 Jenkins를 띄워 파이프라인 전체 흐름을 한 번 확인하고 싶다.
   그래야 Jenkins 배선(credential 주입, checkout, 스테이지 순서)까지 검증된다.
7. 개발자로서, 로컬 Jenkins가 기동만으로 VPS와 같은 Job을 갖기를 원한다. 그래야 매번
   Job을 손으로 만들지 않는다.
8. 개발자로서, push하지 않은 커밋으로 로컬 파이프라인을 테스트하고 싶다. 그래야
   "테스트하려면 먼저 push"라는 순환을 피한다.
9. 개발자로서, 로컬에서 DB를 비운 상태로 시작하고 끝나면 깔끔히 지우고 싶다.

## 환경 이식성

10. 개발자로서, Windows PowerShell에서 Git Bash로 전환하지 않고 배포 스크립트를 실행하고
    싶다.
11. 개발자로서, Mac과 Windows에서 같은 명령으로 같은 결과를 얻고 싶다.
12. 개발자로서, `.sh` 파일이 어느 OS에서 checkout되어도 LF를 유지하기를 원한다. 그래야
    `\r: command not found`를 겪지 않는다.
13. 개발자로서, 로컬에서 검증한 설정이 환경변수 교체만으로 VPS에 적용되기를 원한다.
14. 개발자로서, 나중에 별도 test 서버를 추가할 때 `.env` 한 벌만 늘리면 되기를 원한다.

## 권한과 경로

15. 운영자로서, 배포 작업에 `sudo`가 필요하지 않기를 원한다.
16. 운영자로서, 컨테이너가 만든 파일의 소유권 때문에 배포가 막히지 않기를 원한다.
17. 운영자로서, 데이터(DB, 인증서)가 named volume에 있기를 원한다. 그래야 호스트 경로가
    환경마다 다른 문제를 겪지 않는다.
18. 운영자로서, 설정 파일은 레포 상대 경로로 bind mount되기를 원한다. 그래야 호스트에서
    편집할 수 있다.

## Jenkins 설정 관리

19. 운영자로서, Jenkins volume이 유실되어도 기동만으로 Job과 설정이 복원되기를 원한다.
20. 운영자로서, plugin 목록에 최상위 plugin만 적고 하위 의존성은 자동 해석되기를 원한다.
    그래야 94줄짜리 목록을 읽지 않는다.
21. 운영자로서, plugin과 base image 버전이 고정되기를 원한다. 그래야 재빌드 시점에 따라
    다른 Jenkins가 나오지 않는다.
22. 운영자로서, Jenkins 설정 변경 이력이 git에 남기를 원한다.
23. 운영자로서, GUI에서 변경한 설정이 재기동 시 사라진다는 사실이 문서에 명시되기를
    원한다. 그래야 GUI에서 고치고 날아가는 일을 겪지 않는다.

## Secret 관리

24. 운영자로서, secret을 암호화해 레포에 커밋하고 싶다. 그래야 로컬·CI·VPS가 같은 파일을
    본다.
25. 운영자로서, secret 변경 이력이 git에 남기를 원한다.
26. 개발자로서, 로컬에서 VPS와 같은 Basic Auth로 notes에 접속하고 싶다.
27. 운영자로서, 복호화 key를 홈 디렉터리에 두고 `sudo` 없이 쓰고 싶다.
28. 운영자로서, Jenkins가 credential로 복호화 key를 받기를 원한다. 그래야 key가 호스트에
    노출되지 않는다.
29. 운영자로서, Jenkins volume 유실 시 `github-pat`까지 복원되기를 원한다. 그래야 Job만
    복원되고 checkout이 실패하는 반쪽 복구를 피한다.

## 프로젝트 추가와 배포

30. 운영자로서, 새 프로젝트를 붙일 때 `vps-infra`를 수정하지 않고 싶다.
31. 프로젝트 개발자로서, 내 레포에서 `Dockerfile`과 `compose.yml`을 소유하고 싶다.
32. 운영자로서, 새 서브도메인 추가 시 수정할 파일이 하나이기를 원한다.
33. 운영자로서, Quartz 배포가 깨졌을 때 이전 이미지 태그로 되돌리고 싶다. 현재는 재빌드
    외에 복구 수단이 없다.
34. 운영자로서, 한 프로젝트 배포가 다른 프로젝트를 재생성하지 않기를 원한다.
35. 운영자로서, Jenkins가 자기 자신을 재시작해 빌드가 죽는 일이 없기를 원한다.

## 운영 안정성

36. 운영자로서, Jenkins가 메모리를 과도하게 쓰면 Jenkins만 제한되기를 원한다. VPS에
    swap이 없어 OOM 시 프로세스가 즉사하므로 postgres가 희생되면 안 된다.
37. 운영자로서, `docker ps` 결과에 정체를 알 수 없는 컨테이너가 없기를 원한다.
38. 운영자로서, 배포 경로가 하나이기를 원한다. 그래야 두 경로가 함께 낡지 않는다.
39. 개발자로서, push 시점에 설정 문법 오류가 자동 검증되기를 원한다.

# 구현 결정

## 모듈과 seam

배포 로직을 **스크립트 모듈**로 분리한다. 인터페이스는 인자와 종료 코드다.

- 배포 대상 판정: 두 개의 git 리비전을 받아 대상 문자열(`portal` | `all`)을 stdout으로
  낸다. 부수효과가 없다.
- 배포 실행: 대상 문자열을 받아 compose를 적용한다.
- 헬스체크: 도메인을 환경변수로 받는다. 현재 `health.kkh-hub.tech`가 하드코딩되어 있어
  로컬에서 실패하므로 이를 변수화한다.

Jenkinsfile에는 **오케스트레이션만** 남긴다: 스테이지 구조, 타임아웃, 동시성 옵션,
credential 주입. 판정 로직 같은 Groovy 코드는 남기지 않는다.

## nginx 설정

`nginx/conf.d/*.conf`를 `nginx/templates/*.conf.template`로 옮긴다. nginx 공식 이미지
entrypoint가 기동 시 `envsubst`로 치환하므로 새 의존성이 없다.

환경변수 계약:

| 변수 | 로컬 | VPS |
|------|------|-----|
| `BASE_DOMAIN` | `localhost` | `kkh-hub.tech` |
| `NGINX_LISTEN` | `80` | `443 ssl` |
| `TLS_MODE` | `none` | `live` |

`TLS_MODE`는 include할 파일을 고른다. `none`은 빈 파일, `live`는 인증서 경로를 담은
파일이다. 서비스 1개 = 템플릿 1개 규칙을 유지한다.

`00-http-challenge.conf`의 `server_name` 목록도 템플릿화 대상이다. 새 도메인을 여기에
추가하지 않으면 인증서 발급이 실패하는 현재 함정이 유지되어야 한다.

## 경로와 볼륨

배포 경로를 홈 디렉터리 아래 `app/`로 옮긴다. Jenkins 컨테이너에도 **같은 경로로**
마운트한다. Jenkins가 `docker.sock`을 사용하므로 파이프라인의 `docker run -v` 경로는
호스트 기준이며, 컨테이너 안/밖 경로가 일치해야 한다.

용도별 원칙:

- **데이터**(DB, Redis AOF, 인증서, 빌드 산출물) → named volume
- **설정**(nginx 템플릿, 스크립트) → 레포 상대 경로 bind mount
- **Jenkins 워크스페이스** → 절대 경로 bind mount (위 제약 때문에 불가피)

`/opt/quartz-site`와 `/opt/nginx-auth`에 대한 의존을 제거한다. 전자는 Quartz 이미지화로,
후자는 SOPS 관리로 흡수된다.

## Jenkins 설정

- `plugins.txt`: 최상위 plugin만 버전 고정. 하위 의존성은 `jenkins-plugin-cli`가
  MANIFEST를 읽어 자동 해석한다. 필요한 최상위는 `workflow-aggregator`, `git`,
  `github`, `credentials-binding`, `matrix-auth`, `timestamper`, `ws-cleanup`,
  `build-timeout`, `docker-workflow`, 그리고 새로 추가하는 `configuration-as-code`와
  `job-dsl`이다. 후자 둘은 현재 미설치다.
- `jenkins.yaml`: 시스템 설정(anonymous read 차단, signup 차단)과 job-dsl seed.
- Job 정의: 현재 `quartz-deploy` 설정에서 재현할 항목은 SCM URL, credential
  `github-pat`, 브랜치 `*/main`, `GitHubPushTrigger`, `scriptPath: Jenkinsfile`,
  그리고 `lightweight: false`다. 마지막 항목은 트리거 판정에 필요하다.
- SCM URL은 job-dsl 변수로 둔다. 로컬은 로컬 경로, VPS는 GitHub URL을 받는다.
- base image를 버전 태그로 고정한다. `nginx`, `postgres`, `redis`, `certbot/certbot`도
  같이 고정한다. `certbot/certbot`은 현재 태그가 없어 `latest`로 동작한다.
- Jenkins에만 `mem_limit`과 JVM heap 상한을 둔다.

## Secret

SOPS + age로 암호화한다. 대상은 `.env`, Basic Auth 파일, `github-pat`이다.
복호화 key는 VPS의 `~/.config/sops/age/keys.txt`에 두고, Jenkins에는 credential
(secret file)로 등록한다. GitHub Secrets에는 key 하나만 둔다.

## tools 컨테이너

스크립트 실행 진입점을 컨테이너로 둔다. 호스트에서는 `docker compose run --rm tools ...`만
실행하므로 PowerShell/zsh 구분이 사라진다. 내용은 git과 필요한 CLI를 담은 얇은 이미지다.
`docker.sock`을 마운트해 컨테이너 안에서 docker 명령이 동작하게 한다.

명령 진입점은 compose 명령을 직접 쓴다. Makefile은 두지 않는다. Windows에 `make`가
없어 지금 겪는 문제 유형이 재발한다.

## Compose 프로젝트 경계

- `vps-infra/compose.yml`: nginx, certbot, postgres, redis, portal, tools
- `vps-infra/jenkins/compose.yml`: jenkins. `vps_proxy`를 `external: true`로 참조.
  분리를 유지하는 이유는 Jenkins가 자기 자신을 재생성하면 실행 중인 파이프라인이 죽기
  때문이다. 로컬도 같은 구조를 유지한다.
- 각 프로젝트 레포: 자기 `Dockerfile` + `compose.yml`. `vps_proxy`를 external로 참조.

compose profile은 도입하지 않는다. Jenkins가 이미 별도 파일이므로 선택적 기동은 해당
디렉터리에서 `up`하지 않는 것으로 충분하다.

## GitHub Actions

배포 workflow를 삭제하고 **검증 전용**으로 전환한다: compose 문법 검증, nginx 설정 검증,
SOPS 파일 무결성. 현재 workflow는 `workflow_dispatch`에서 `github.event.before`를
참조하는데 그 값이 비어 있어 항상 `target=all`로 떨어진다.

## 정리 대상

- `.env`의 traefik 잔재(`ACME_EMAIL`, `TRAEFIK_DASHBOARD_AUTH`)
- `.gitattributes` 신규 추가(`*.sh text eol=lf`). SOPS나 tools 컨테이너를 쓰더라도
  CRLF는 컨테이너 안에서도 깨지므로 필수다.

# 테스트 결정

## 좋은 테스트의 기준

**외부에서 관찰 가능한 행동만** 검증한다. 렌더된 conf 파일의 내용을 diff하거나, 스크립트
내부 변수를 확인하는 방식은 쓰지 않는다. 구현을 바꾸면 깨지는 테스트는 가치가 낮다.

## Seam 1 — 스크립트 (인자 in, stdout/exit code out)

배포 대상 판정이 유일한 비자명 분기 로직이므로 여기에 검증을 둔다. 가짜 커밋 두 개로
`portal`과 `all` 양쪽이 나오는지 확인하는 `assert` 기반 셸 검증 하나. 프레임워크는
도입하지 않는다.

경계 조건: 변경 파일이 없을 때, `portal/` 밖 파일이 섞였을 때, `portal/`만 있을 때.
현재 Jenkinsfile 로직은 `files.every {}`를 쓰는데 빈 리스트에서 `true`가 되므로 변경
파일이 없을 때 `portal`로 판정된다. 이 동작을 유지할지 고치는지가 검증으로 드러난다.

## Seam 2 — 기동된 스택에 HTTP 요청

nginx 관련 검증을 **모두 이 seam 하나로** 처리한다. `curl`로 상태 코드와 본문을 본다.

- 각 서브도메인이 자기 서비스로 라우팅되는가
- 정적 사이트의 `try_files` 규칙이 확장자 없는 경로를 처리하는가
- Basic Auth가 걸린 경로가 401을 주는가
- 로컬에서 HTTP로 기동되는가(TLS 모드 분기)

렌더된 conf를 검사하지 않는 이유는, 200 응답이 렌더·라우팅·네트워크 연결을 동시에
증명하기 때문이다. `nginx -t`는 CI 검증(위 Actions)에서 문법만 본다.

## Seam 3 — SOPS 왕복

암호화 파일을 복호화해 기대한 키가 나오는지 확인한다. key 배치 오류를 잡는 것이 목적이다.

## Jenkins

별도 자동 테스트를 두지 않는다. 파이프라인은 seam 1의 스크립트를 호출하는 얇은
오케스트레이션이므로, 로컬 Jenkins에서 수동 빌드 1회로 배선(credential 주입, checkout,
스테이지 순서)을 확인한다.

두 개의 검증 루프로 운용한다.

| 루프 | 수단 | 검증 대상 | 소요 |
|------|------|-----------|------|
| 빠른 루프 | seam 1, 3 | 로직 버그 | 수초 |
| 느린 루프 | seam 2 + 로컬 Jenkins 수동 빌드 | 배선 버그 | 수분 |

## 기존 테스트 관행

`portal/main_test.go`가 유일한 기존 테스트다. `t.TempDir()`로 실제 파일을 쓰고 핸들러에
HTTP 요청을 보내 상태 코드와 본문을 확인한다. 즉 **모킹 없이 외부 행동을 검증**하는
방식이며, 위 seam 설계가 같은 관행을 따른다.

# 작업 순서

| 단계 | 내용 | 검증 |
|------|------|------|
| 0 | `.gitattributes`, 이미지 버전 고정, traefik 잔재 제거, 배포 workflow 삭제 | 무해 |
| 1 | `tools` 컨테이너 + 스크립트 로직 분리 | seam 1 |
| 2 | nginx 템플릿화 | seam 2 (로컬 HTTP) |
| 3 | SOPS 도입 | seam 3 |
| 4 | `plugins.txt` + JCasC + job-dsl, 로컬 Jenkins | Job 자동 생성 확인 |
| 5 | portal로 전체 흐름 검증 | 로컬 Jenkins → portal 재배포 |
| 6 | VPS 적용: `app/` 이전, JCasC 전환 | portal 정상, Job 복원 |
| 7 | Quartz 이미지화 (`quartz-site-private` 레포) | rollback 포함 |
| 8 | 신규 프로젝트 1개 추가 | 신구조로 처음부터 |

portal을 먼저 검증 대상으로 쓰는 이유는, 이미 `vps-infra` 안에 있어 레포 추가가 없고
실제 빌드(`npm ci` + `go build`)를 겪으면서도 장애 영향이 작기 때문이다.

# 범위 외

- **별도 test 서버 도입.** 로컬을 staging 대용으로 쓴다. 필요해지면 `.env` 한 벌을
  추가하는 것으로 확장된다.
- **로컬 HTTPS와 로컬 webhook.** 로컬은 HTTP만 쓰고, Jenkins는 수동 빌드로 트리거한다.
  webhook은 설정 일치 문제이지 로직 문제가 아니다.
- **GHCR 도입과 빌드 외부화.** [ADR 0001](/adr/0006-jenkins-builds-on-vps.md) 참조.
  CPU 경합이 실제로 관측되면 재검토한다.
- **Vault 등 secret manager.** [ADR 0005](/adr/0010-sops-secrets.md) 참조.
- **모든 서비스에 `mem_limit`.** Jenkins만 적용한다. 나머지는 합쳐 40MB 수준이다.
- **portal 레포 분리.** 인프라와 생명주기가 같으므로 `vps-infra`에 유지한다.
- **하위 의존성 plugin 버전 고정.** 가독성을 위한 의식적 trade-off다.
- **기존 번호 없는 ADR 파일명 정규화.** inbound 링크가 깨진다.

# 알려진 리스크

1. **JCasC 전환 시 기존 설정과 충돌.** VPS에 plugin 94개와 GUI Job 2개가 있다. 단계 4를
   로컬에서 먼저 겪고, 단계 6 전에 Jenkins volume을 백업한다.
2. **age key 분실 시 복호화 불가.** key 백업이 운영 요구사항이 된다.
3. **하위 의존성 버전 미고정.** 문제 발생 시 해당 항목만 추가 고정한다.
4. **로컬 SCM 방식이 VPS와 다름.** job-dsl 변수로 흡수하고 단계 4~5에서 검증한다.

# 현재 상태 실측

2026-08-23 기준. 이 spec의 판단 근거다.

```txt
컨테이너   7개 정상 (고아 certbot과 hello-world 잔재는 정리 완료)
메모리     7.9GB 중 2.0GB 사용 (Jenkins 1.0GB, 그 외 합계 ~40MB)
디스크     96GB 중 12GB (13%)
swap       없음
Jenkins    2.568.1, plugin 94개, Job 2개, credential 1개
인증서     kkh-hub.tech SAN 1장, 만료 2026-11-07
```

# 관련 개념

- [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md)
- [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)
- [nginx 설정의 환경 템플릿화](/adr/0008-nginx-env-templates.md)
- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
- [시스템 아키텍처 개요](/architecture/system-overview.md)
