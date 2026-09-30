---
type: Review
title: Jenkins·nginx 보안 및 운영 리뷰 2026-09-11
description: 저장소 설정과 ADR을 비교한 정적 리뷰, 운영 확인이 필요한 사항과 개인 VPS 개선 우선순위.
tags: [review, security, jenkins, nginx, operations]
timestamp: 2026-09-11T00:00:00+09:00
---

# 범위와 판단 기준

저장소의 Jenkinsfile, Jenkins JCasC/Job DSL, Compose, nginx 템플릿,
배포·검증 스크립트와 ADR 0001~0010을 리뷰했다. VPS 접속, 실제 Jenkins 설정,
인증서, 방화벽, GitHub branch protection, 설치된 plugin 취약점은 확인하지 않았다.
아래 P1은 운영 장애 또는 민감 정보 노출을 막기 위해 우선 보완할 항목,
P2는 재현성·운영 안전성 개선 항목이다. 실제 침해나 장애 발생을 뜻하지 않는다.

[인수 절차](/runbooks/local-first-handover.md)의 2026-08-24 기록은 nginx 전환 완료,
Jenkins JCasC 미적용을 명시했다. 이후 2026-09-28에 VPS Jenkins가 JCasC 이미지로
동작함을 확인했다.

# 확인된 보완점

## P1: nginx 템플릿 변경이 자동 배포에서 반영되지 않을 수 있다

근거: `scripts/deploy.sh:52`, `compose.yml:20`, `compose.yml:21`.
전체 배포는 `docker compose up -d --build --wait`를 실행하지만 nginx 재생성이나
설정 재생성/reload를 명시하지 않는다. bind mount 안의 템플릿 내용만 바뀌면
Compose 서비스 정의와 이미지가 같으므로 nginx가 재생성되지 않는다.
entrypoint의 envsubst도 다시 실행되지 않아 이전 설정으로 계속 서비스할 수 있다.
서비스 문서는 `--force-recreate nginx`를 요구하지만 스크립트는 이를 구현하지 않는다.

최소 보완은 후보 설정 렌더링과 `nginx -t` 성공 후 nginx만 강제 재생성하는 것이다.
짧은 중단을 없애려면 렌더링 결과를 안전하게 교체하고 reload하는 흐름으로 발전시킨다.
검증은 템플릿만 바꾼 배포 후 실제 응답이 변경됐는지 확인해야 한다.

## P1: 인증서 갱신과 nginx 재로딩이 연결되지 않았다

근거: `compose.yml:56`, `nginx/tls/live.conf:8`.
certbot renew 루프는 파일만 갱신하며 nginx가 새 인증서를 읽도록 하는 단계가 없다.
별도 호스트 hook/timer가 없다면 nginx는 reload 또는 재시작 전까지 기존 인증서를 제공한다.
그 결과 파일 갱신은 성공했지만 외부 HTTPS는 만료될 수 있다.

호스트 timer에서 갱신과 `nginx -t` 및 reload를 함께 관리하는 방법이 단순하다.
갱신 성공시에만 동작시키려면 certbot deploy-hook과 호스트 측 알림 처리를 연결한다.
certbot 컨테이너에 Docker socket을 추가하는 방식은 권한을 불필요하게 늘린다.
외부에서 제공되는 인증서의 만료일도 별도로 감시한다.

## P1: 비공개 notes의 정적 자산에 공유 캐시를 허용한다

근거: `nginx/templates/notes.conf.template:37`.
Basic Auth로 보호하는 이미지·JS·CSS에 30일 캐시와 `public, immutable`을 설정한다.
RFC 9111의 public은 Authorization 요청 응답도 공유 캐시가 재사용할 수 있게 한다.
현재 공유 캐시 존재나 유출은 확인하지 않았지만 향후 CDN 등을 붙이면 비공개 자산이
인증 경계를 벗어날 수 있는 정책이다.

개인 노트는 `private` 또는 민감도에 따라 `no-store`로 바꾼다.
또한 확장자만으로 immutable을 적용하지 말고 실제 콘텐츠 해시가 있는 파일만 대상으로 한다.
인증 실패 상태뿐 아니라 성공 응답의 Cache-Control도 테스트한다.

## P1: 운영에서 공개 테스트 비밀번호로 시작할 수 있다

근거: `compose.yml:30`, `compose.yml:36`.
BASIC_AUTH_HTPASSWD가 누락되면 공개 fixture인 test/test가 사용되며 포트는 모든
호스트 인터페이스에 publish된다. 운영 .env가 실제로 누락됐다는 뜻은 아니다.
로컬 편의 기본값을 운영 진입점에서도 허용하는 것이 문제다.

운영 배포 전 TLS_MODE=live, 운영 도메인, 실제 htpasswd 경로를 필수 검증하고
fixture 사용이면 실패시킨다. 로컬과 운영 secret 값은 분리하되 설정 구조는 공유한다.

## P1: 배포 범위가 마지막 커밋 하나로 제한된다

근거: `Jenkinsfile:55`, `Jenkinsfile:75`.
git pull은 여러 커밋을 가져올 수 있지만 판정에는 HEAD~1..HEAD만 사용한다.
nginx 변경 다음 portal 변경을 한 번에 push하면 portal만 배포돼 nginx 변경이 누락된다.
실패 후 재배포에도 마지막 성공 배포 이후의 누적 변경을 보장하지 못한다.

마지막 성공 배포 SHA와 이번 고정 SHA를 비교하고, 검증 성공 후에만 성공 SHA를 갱신한다.
최초 배포 기준이 없으면 명시적 전체 배포로 처리한다. SCM에서 읽은 Jenkinsfile과
APP_DIR에서 나중에 pull한 코드가 서로 다른 커밋일 수 있으므로 배포 SHA도 통일한다.
`git pull --ff-only`는 변경과 충돌하지 않는 로컬 수정까지 거부하지 않으므로
운영 배포는 깨끗한 checkout임을 별도로 확인해야 한다.

## P1: portal 배포 실패를 health 검사에서 놓칠 수 있다

근거: `nginx/templates/portal.conf.template:37`, `scripts/deploy.sh:39`,
`scripts/healthcheck.sh:46`, `compose.yml:70`.
portal upstream은 시작 시 해석하는 고정 proxy_pass이고 nginx를 유지한 채 portal만
재생성한다. IP가 바뀌면 nginx가 이전 IP를 계속 사용할 수 있다. Jenkins 템플릿에 있는
동적 resolver 패턴 또는 지원 버전의 upstream resolve를 portal에도 적용할 수 있다.

portal에는 Compose healthcheck가 없고 배포 후 HTTP 검사도 whoami만 확인한다.
portal이 502여도 DB·Redis·whoami가 정상이면 배포 성공으로 처리될 수 있다.
portal 자체 readiness와 nginx를 통한 portal 응답·배포 SHA를 함께 검증한다.

## P2: CI 검증 결과가 배포를 막는 조건이 아니다

근거: `.github/workflows/validate.yml:5`, `jenkins/jobs.groovy:45`, `Jenkinsfile:84`.
main push 후 Actions 검증과 Jenkins 배포가 별도로 시작된다. Jenkins는 Actions
성공을 기다리지 않으며 nginx 후보 설정 검사도 직접 실행하지 않는다.
GitHub ruleset 적용 여부는 미확인이다. required checks와 main 보호를 적용하고,
배포에도 같은 SHA에 대한 필수 사전 검증을 둔다.

## P2: Jenkins 메모리 제한이 호스트 이미지 빌드까지 제한하지 않는다

근거: `jenkins/compose.yml:14`, `jenkins/compose.yml:54`, `jenkins/jenkins.yaml:12`,
[ADR 0006](/adr/0006-jenkins-builds-on-vps.md).
Jenkins 컨테이너의 2GB 제한은 Docker socket으로 호스트 daemon에 요청한
BuildKit 작업의 전체 메모리 상한이 아니다. Job별 disableConcurrentBuilds도
서로 다른 Job 간 동시 빌드를 막지 않는다.

초기에는 전역 빌드 동시성 1로 시작하고 실제 빌드 시 호스트 메모리와 앱 지연을 측정한다.
필요하면 별도 docker-container builder에 memory/CPU 옵션을 적용한다.
ADR의 유휴 리소스 실측은 유용하지만 빌드 피크와 운영 요청 지연의 증거를 추가해야 한다.

# Jenkins 보안 경계

`jenkins/compose.yml:54`의 Docker socket과 built-in executor 2개는
Pipeline 및 빌드 코드에 Jenkins home과 호스트 Docker 제어 권한을 부여한다.
rootful Docker에서는 사실상 호스트 관리자 수준으로 취급해야 한다.
`jenkins/jenkins.yaml:36`은 Job DSL script security도 전역으로 끈다.
현재 anonymous read/signup 차단은 좋은 설정이지만 이 권한 경계를 제거하지 않는다.

개인 소유의 신뢰하는 main만 실행하는 학습 환경이라면 명시적으로 수용할 수 있다.
외부 PR과 신뢰하지 않는 프로젝트 코드는 이 경로에서 실행하지 않는다.
GitHub PAT는 저장소별 최소 권한으로 제한하고 운영 age key의 GLOBAL 범위와
환경변수 주입도 재검토한다. Credential 파일로 등록해도 원본 key가 컨테이너
환경변수에 남는 현재 구현은 호스트나 controller 침해로부터 key를 숨기지 못한다.

권장 후속은 controller executor 0과 전용 agent 분리다. 같은 호스트 Docker socket을
agent에 그대로 주면 호스트 격리까지 얻는 것은 아니다. 배포 권한이 없는 빌드 영역과
승인된 코드만 실행하는 배포 영역의 분리는 신뢰 범위가 넓어질 때 진행한다.
Jenkins UI 접근은 VPN/IP 제한을 검토하되 GitHub webhook 경로와 전달·서명 검증을
따로 설계한다. 실제 webhook secret과 설치 plugin 보안 경고는 VPS에서 확인해야 한다.

# ADR 및 운영 문서 평가

| 결정 | 평가와 보완 |
|---|---|
| 0002 공통 DB/Redis | 개인 VPS에 적절하다. 앱 추가 시 DB별 일반 사용자와 Redis ACL을 적용한다. |
| 0003 restart policy | 재부팅 복구에 적절하다. unhealthy 상태의 자동 복구나 백업을 대신하지 않는다. |
| 0006 VPS 빌드 | Jenkins 학습 목적과 규모에 맞는다. 빌드 피크 측정 및 builder 제한 설명은 보완해야 한다. |
| 0007 독립 Compose | 소유권 경계가 명확하다. Quartz 이미지화와 이전 이미지 복구는 아직 후속 작업이다. |
| 0008 환경 템플릿 | 로컬 재현성 확보에 효과적이다. 배포 시 재렌더링과 TLS 최초 발급·갱신 검증까지 연결한다. |
| 0009 JCasC | 복구성과 변경 추적에 유리하다. 운영 미적용 상태를 명시하고 전환 검증을 끝내야 한다. |
| 0010 SOPS | 개인 인프라에 적절하다. key 외부 백업, 환경별 secret 분리, 최소 복호화 권한이 필요하다. |

문서 불일치도 복구 사고로 이어질 수 있다. `okf/services/nginx.md`의 최초 발급
예시는 현재 Compose에 필요한 `--entrypoint certbot`이 빠져 renew 루프를 실행한다.
빈 인증서 volume에서는 live nginx가 먼저 시작되지 않으므로 HTTP bootstrap 순서가 필요하다.
인수 절차 상단은 단계 6~8 미구현이라고 하지만 하단은 단계 6 일부 완료로 기록한다.
ADR 0004의 Actions 중지 설명도 ADR 0001의 검증 전용 전환과 구분해 읽어야 한다.
이번 리뷰는 기존 결정을 변경하지 않으며 운영 문서 교정은 후속 작업으로 남긴다.

# 백엔드 개발 관점의 다음 작업

1. 이미지에 Git SHA 태그를 붙이고 앱이 실행 버전을 응답하게 한다. 이전 이미지 보관과
   한 번의 복구 명령을 만든다. DB migration은 이전 앱과 호환되는 순서로 적용한다.
2. 앱마다 readiness, graceful shutdown, migration 실행 주체를 정한다.
   Spring Boot라면 필요한 health 경로만 노출하고 Actuator 전체를 공개하지 않는다.
3. nginx에 request ID, request_time, upstream_response_time을 남기고 앱 로그와 연결한다.
   forwarded header를 신뢰할 프록시 범위도 명시한다.
4. 먼저 외부 HTTPS·인증서 만료·디스크 여유·백업 실패·배포 실패 알림을 붙인다.
   `OBSERVABILITY.md`의 전체 구성 도입보다 실제 장애 감지가 우선이다.
5. Jenkins buildDiscarder와 Docker 로그 회전, BuildKit 캐시 보존량을 정한다.
   호스트 daemon 로그 정책은 확인하지 않았으므로 현재 무제한이라고 단정하지 않는다.
6. 기존 stage6 백업과 복원 검증 기록은 장점이다. 같은 VPS의 백업에 더해 외부 복사본과
   주기적 복구 연습을 운영한다. DB 일일 백업이라면 최대 하루 유실 허용 여부를 정한다.
7. 알 수 없는 Host를 거부하는 기본 server, notes 로그인 시도 제한, HTTPS 안정화 후
   HSTS, 실제 해시 파일만의 immutable 캐시를 적용한다. Jenkins WebSocket 헤더는
   공식 예제처럼 조건부 Connection map으로 정리한다.

# 검증 결과와 한계

- `bash scripts/test-select-target.sh`: 6개 케이스 통과. 호출자가 HEAD~1만 전달하는
  누적 변경 문제를 검증하는 테스트는 아니다.
- `bash scripts/check-sops.sh`: 암호화 파일 4개 형식 검사 통과.
  복호화/MAC 검증이나 저장소 전체의 평문 secret 탐지를 의미하지 않는다.
- 실제 nginx 기동·라우팅 테스트, TLS 갱신, Jenkins 실행, 운영 침투 테스트는 수행하지 않았다.
- 이미지 태그와 plugin의 실제 설치 버전 및 CVE 안전성은 이 리뷰에서 보증하지 않는다.

# 관련 개념

- [시스템 아키텍처](/architecture/system-overview.md)
- [Jenkins 배포](/services/jenkins-deploy.md)
- [nginx](/services/nginx.md)
- [인수 절차](/runbooks/local-first-handover.md)

# Citations

- [Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up/)
- [nginx 설정 재로딩](https://nginx.org/en/docs/control.html)
- [Certbot 갱신 hook](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)
- [RFC 9111 public 캐시](https://www.rfc-editor.org/rfc/rfc9111.html#section-5.2.2.9)
- [Docker Engine 보안](https://docs.docker.com/engine/security/)
- [Jenkins controller 격리](https://www.jenkins.io/doc/book/security/controller-isolation/)
- [BuildKit docker-container driver 자원 제한](https://docs.docker.com/build/builders/drivers/docker-container/)
- [nginx upstream resolve](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#resolve)
- [Jenkins nginx 공식 예제](https://www.jenkins.io/doc/book/system-administration/reverse-proxy-configuration-with-jenkins/reverse-proxy-configuration-nginx/)
