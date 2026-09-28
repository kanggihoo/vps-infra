---
type: Decision
title: 인증서 갱신을 컨테이너 안에서 끝낸다
description: 호스트 systemd timer 대신 상주 certbot 컨테이너가 갱신하고 nginx가 하루 한 번 스스로 reload한다.
tags: [certbot, nginx, tls, docker-compose]
timestamp: 2026-09-28T00:00:00+09:00
---

# 결정

인증서 갱신을 Compose 안에서 끝낸다. [spec 0002](/spec/0002-infra-review-remediation.md)의
호스트 systemd timer 방식을 대체한다.

- `certbot` 서비스가 상주하며 12시간마다 `certbot renew`를 실행한다. 만료 30일 이내일 때만
  실제로 갱신한다.
- `nginx` 서비스가 하루 한 번 `nginx -s reload`로 갱신된 인증서를 읽는다. reload는 연결을
  끊지 않는다.
- nginx entrypoint는 인자가 있으면 루프 없이 그 명령만 실행한다. `deploy.sh`의
  `compose run nginx nginx -t` 검증 경로를 유지하기 위해서다.

# 이유

systemd timer는 **설치되지 않은 채로** 한 달 넘게 방치되었다. 설치에 sudo가 필요하고
배포 파이프라인이 설치할 수 없어서, 레포에는 있는데 VPS에는 없는 상태가 생겼다.
2026-09-28 전체 배포가 옛 상주 certbot 컨테이너를 `scale: 0`으로 제거하자 자동 갱신을
하는 주체가 하나도 남지 않았다.

Compose 안에서 끝내면 `git push` → Jenkins 배포만으로 갱신 구성이 VPS에 반영된다. 호스트
설정(root 소유 env 파일, unit 파일)이 사라져 레포와 운영 상태가 어긋날 여지가 없다.

certbot 컨테이너가 nginx를 직접 reload하려면 Docker socket이나 PID namespace 공유가
필요하다. 전자는 certbot에 host 제어 권한을 주고, 후자는 nginx가 재생성될 때마다 연결이
끊긴다. 하루 주기 reload는 갱신 뒤 최대 하루 늦게 반영되지만 갱신이 만료 30일 전에
일어나므로 문제가 없다.

# 결과

- `systemd/`와 `scripts/renew-certificates.sh`를 삭제했다.
- 로컬에서도 certbot 컨테이너가 뜨지만 인증서가 없어 `No renewals were attempted`만 남긴다.
- 새 서브도메인은 여전히 `CHALLENGE_DOMAINS` 수정과 `certbot certonly --expand` 1회가 필요하다.
  HTTP-01은 이름마다 검증하므로 와일드카드 인증서를 받을 수 없다. 와일드카드는 DNS API가 있는
  DNS 관리처(DNS-01)가 전제다.
- 옛 상주 컨테이너가 reload하지 않던 결함(갱신해도 nginx가 옛 인증서를 계속 씀)도 함께 해소된다.

# 관련 개념

- [nginx 리버스 프록시](/services/nginx.md)
- [nginx 설정의 환경 템플릿화](/adr/0008-nginx-env-templates.md)
- [Jenkins·nginx 리뷰 보완](/spec/0002-infra-review-remediation.md)
