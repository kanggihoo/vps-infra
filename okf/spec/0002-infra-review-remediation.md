---
type: Specification
title: Jenkins·nginx 리뷰 보완
description: 2026-09-11 인프라 리뷰에서 저장소 변경으로 해결할 수 있는 배포, nginx, 인증서 갱신 보완 범위.
tags: [spec, jenkins, nginx, tls, deployment]
timestamp: 2026-09-13T00:00:00+09:00
---

# 목적

[Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md)의
저장소 수준 P1 항목을 고친다. 실제 VPS 접근이 필요한 GitHub ruleset, webhook secret,
방화벽, Jenkins plugin 상태는 이 변경 범위에 넣지 않는다.

# 배포 규칙

Jenkins는 checkout 갱신 뒤의 SHA를 이번 배포 SHA로 고정한다. 자동 대상 선택은
`last-successful-sha..배포 SHA`의 누적 변경을 사용한다. healthcheck까지 성공한 경우에만
`last-successful-sha`를 갱신한다.

배포 상태는 checkout의 `.deploy-state/last-successful-sha`에 둔다. Git은 이 파일을
추적하지 않는다. 상태 파일이 없거나 현재 SHA의 조상이 아니면 안전하게 전체 배포한다.

# nginx와 portal

전체 배포는 후보 nginx 설정의 `nginx -t` 성공 뒤 nginx를 강제 재생성한다. 템플릿만
변경해도 envsubst 결과가 갱신된다. portal은 nginx가 Docker DNS로 upstream을 요청마다
다시 해석하도록 설정한다. portal만 재생성해 IP가 바뀌어도 nginx 재시작이 필요 없다.

healthcheck는 기존 health route와 nginx를 통한 portal 응답을 모두 확인한다.

# 운영 환경 보호

TLS live 모드에서는 공개 notes fixture를 사용한 배포를 거부한다. notes의 인증된 정적
자산은 `Cache-Control: private, no-store`로 응답한다.

# 인증서 갱신

certbot Compose 서비스의 상주 갱신 루프를 제거한다. 호스트 systemd timer가 12시간마다
`scripts/renew-certificates.sh`를 실행한다. 스크립트는 certbot 갱신 성공 뒤 nginx 설정을
검사하고 reload한다. systemd unit은 `APP_DIR`만 가진 root 소유 환경 파일을 읽는다.

# Jenkins 자원

Jenkins controller executor는 전역 1개로 제한한다. Docker socket을 통해 실행되는
BuildKit 작업은 Jenkins container 메모리 제한 밖에 있으므로, 실제 빌드 중 host 메모리와
서비스 지연을 측정한 뒤 별도 builder 제한 필요성을 판단한다.

# 검증

- 누적 변경과 상태 파일 예외를 `scripts/test-select-target.sh`에서 검증한다.
- Compose 문법과 local/live nginx 렌더링은 GitHub Actions에서 검증한다.
- 배포 스크립트와 인증서 갱신 스크립트는 실패 시 nginx reload나 상태 SHA 갱신을 하지 않는다.

# 관련 개념

- [Jenkins·nginx 보안 및 운영 리뷰](/architecture/infra-review-2026-09-11.md)
- [Jenkins 배포](/services/jenkins-deploy.md)
- [nginx 리버스 프록시](/services/nginx.md)
