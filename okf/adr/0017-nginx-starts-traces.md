---
type: Decision
title: 외부 요청의 trace는 nginx가 시작한다
description: nginx otel 모듈이 요청마다 trace를 시작해 W3C traceparent로 백엔드에 전파한다. 앱은 새 trace를 만들지 않고 이어받는다.
tags: [observability, tracing, nginx, opentelemetry, tempo]
timestamp: 2026-10-08T00:00:00+09:00
---

# 결정

> 외부 HTTP 요청의 trace는 nginx가 시작하고, W3C `traceparent`로 전파한다.
> 앱은 들어온 `traceparent`를 이어받아 자식 span만 만들고, 샘플링 판단도 nginx를 따른다(parent-based).
> nginx를 거치지 않는 작업(주기 수집, 배치)은 필요할 때 앱이 root span을 시작할 수 있다.

nginx는 `nginx:1.31.4-alpine-otel` 이미지의 otel 모듈을 쓴다.

- 요청마다 nginx span을 만들어 OTLP로 Alloy에 보낸다. Alloy가 Tempo로 넘긴다.
- 샘플링은 100%로 시작한다. `/health`와 probe 요청은 trace하지 않는다.
- access log를 JSON으로 바꾸고 아래 필드를 넣는다.
  - `trace_id`
  - `request_time`
  - `upstream_response_time`
  - `host`
- 백엔드로 `traceparent` 헤더를 전파한다. 계측이 없는 앱은 이 헤더를 무시한다.
- Grafana Loki 데이터소스에 `trace_id` derived field를 둬, 로그 줄에서 Tempo 트레이스로 이동한다.

이번 결정에서 vps-info 코드는 수정하지 않는다.

# 이유

로그에서 트레이스로 이동하려면 모든 요청이 공통 trace id를 가져야 한다. 진입점은 nginx 하나뿐이다.
따라서 nginx가 시작하면 앱 계측 여부와 관계없이 모든 외부 요청에 trace id가 생긴다.

앱마다 trace를 시작하면 같은 요청에 nginx 로그와 앱 로그가 서로 다른 id를 갖게 된다.

샘플링을 하면 로그에는 `trace_id`가 있는데 Tempo에는 트레이스가 없는 줄이 생긴다. 그래서 개인 VPS
트래픽 규모에서는 전수 trace를 택한다.

`traceparent`를 지금 전파해 두면 나중에 vps-info에 SDK를 넣는 순간 nginx span이 root가 되어 이어진다.
nginx 설정을 다시 바꾸지 않아도 된다.

# 결과

- 앱이 OTel SDK를 넣어도 trace id는 만들지 않는다. 하지만 자기 구간(핸들러, DB 쿼리 등)을 보이려면 자식
  span은 만들어야 한다. 그렇지 않으면 트레이스에 nginx span 하나만 남는다.
- 컨테이너끼리의 내부 호출(예: vps-info app → llm)은 호출하는 쪽 SDK가 `traceparent`를 실어 보내야 같은
  trace에 이어진다.
- nginx를 거치지 않는 작업에는 nginx trace가 없다. vps-info `collector`의 주기 수집이 그 예다. trace가
  꼭 필요한 것은 아니다. collector의 생존은 `collector_heartbeat`로, 실행 성공·실패는 로그로 충분하다.
  "어느 단계가 느린가"를 알아야 할 때 root span을 넣는다.
- 봇 스캐닝 등으로 Tempo 용량이 문제가 되면 샘플링을 도입한다. 이때 로그의 `trace_id`와 Tempo의 트레이스가
  1:1이 아니게 된다는 점을 감수한다.

# 관련 개념

- [관측 스택을 VPS에 셀프호스팅하고 Alloy 하나로 수집한다](/adr/0016-self-hosted-observability.md)
- [nginx 리버스 프록시](/services/nginx.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
