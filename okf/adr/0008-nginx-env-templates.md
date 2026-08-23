---
type: Decision
title: nginx 설정의 환경 템플릿화
description: nginx conf를 envsubst 템플릿 한 벌로 유지하고 환경변수만 교체해 로컬과 VPS를 모두 커버한다.
tags: [nginx, local-development, tls, envsubst]
timestamp: 2026-08-23T00:00:00+09:00
---

# 결정

`nginx/conf.d/*.conf`를 `nginx/templates/*.conf.template`로 옮기고, 도메인·리스닝
포트·TLS 모드를 환경변수로 뺀다. nginx 공식 이미지의 entrypoint가 기동 시
`envsubst`로 치환한다.

```nginx
server {
    listen ${NGINX_LISTEN};
    server_name portal.${BASE_DOMAIN};
    include /etc/nginx/tls/${TLS_MODE}.conf;
    location / { proxy_pass http://portal:8080; ... }
}
```

| 변수 | 로컬 | VPS |
|------|------|-----|
| `BASE_DOMAIN` | `localhost` | `kkh-hub.tech` |
| `NGINX_LISTEN` | `80` | `443 ssl` |
| `TLS_MODE` | `none` (빈 파일) | `live` (인증서 경로) |

로컬은 HTTP만 사용한다. `*.localhost`는 브라우저가 자동으로 `127.0.0.1`로 풀어주므로
hosts 파일 수정이 필요 없다.

# 이유

현재 conf는 로컬에서 **기동조차 하지 못한다**. `listen 443 ssl`인데 인증서가 없어
nginx가 시작에 실패하고, `server_name`이 `*.kkh-hub.tech`로 하드코딩되어
`portal.localhost` 요청은 어느 server block에도 매칭되지 않는다.

로컬 nginx는 실제로 버그를 잡는다. 컨테이너 이름·포트 오타, 서비스가 `proxy`
네트워크에 없는 경우(502의 주 원인), `try_files` 규칙, WebSocket 헤더, Basic Auth,
캐시 헤더가 모두 HTTP에서 검증된다. 프로젝트가 여러 개면 이런 배선 오류가 가장 자주
발생한다. TLS만 로컬에서 검증할 수 없고, 그건 VPS에서 1회 확인으로 끝난다.

템플릿화는 환경이 늘어날 때도 유효하다. 별도 test 서버를 두더라도 그 도메인은
`*.kkh-hub.tech`가 아니므로, 템플릿이 없으면 같은 하드코딩 문제가 staging과
production 사이에서 재발한다.

# 결과

- 서비스 추가 시 수정할 파일은 여전히 하나(템플릿 1개)다. conf를 환경별로 두 벌
  유지하면 프로젝트가 늘수록 어긋나므로 채택하지 않았다.
- `envsubst`는 nginx 이미지에 내장되어 있어 새 의존성이 없다.
- 로컬에서는 certbot을 실행하지 않는다. 인증서 관련 관심사가 VPS로 격리된다.
- 별도 test 서버 도입은 추후 판단한다. 도입 시 `.env` 한 벌을 추가하면 된다.

# 관련 개념

- [nginx 리버스 프록시](/services/nginx.md)
- [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)
- [서브도메인 라우팅](/adr/0005-subdomain-routing.md)
