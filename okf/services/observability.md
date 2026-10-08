---
type: Service
title: 관측 스택 (Grafana·Prometheus·Loki·Tempo·Alloy)
description: VPS의 메트릭·로그·트레이스를 Alloy 하나로 모아 Grafana에서 조회하고 Mattermost로 알린다.
tags: [observability, grafana, prometheus, loki, tempo, alloy, monitoring]
timestamp: 2026-10-08T00:00:00+09:00
---

# 개요

`observability/compose.yml`이 띄우는 별도 Compose project(`vps-observability`)다. 결정과 근거는
[ADR 0016](/adr/0016-self-hosted-observability.md), 트레이스 규칙은 [ADR 0017](/adr/0017-nginx-starts-traces.md)에 있다.
외부에는 `grafana.kkh-hub.tech`만 노출되고 Grafana 자체 로그인(admin)으로 들어간다.

```txt
nginx(otel 모듈) ─ span ─┐
Jenkins(OTel plugin) ─ span·메트릭·빌드 로그 ─┤
                                              ▼
모든 컨테이너 stdout ─ Docker API ─▶ Alloy ─▶ Prometheus (메트릭, 15일/5GB)
호스트·컨테이너·probe ─ 내장 exporter ─┘    ├▶ Loki (로그, 7일)
                                           └▶ Tempo (트레이스, 72시간)
                                                 ▲
                                        Grafana ─┘ ─▶ Mattermost 알림
```

# 구성 파일

| 경로 | 내용 | 반영 |
|------|------|------|
| `observability/alloy/config.alloy` | 수집 대상과 경로, cAdvisor 허용 목록, probe 대상 | 재배포(checksum으로 재생성) |
| `observability/prometheus/prometheus.yml` | 보존 기간·크기 | 재배포 |
| `observability/loki/config.yaml` | 보존, 캐시 크기 | 재배포 |
| `observability/tempo/tempo.yaml` | 보존 (Tempo 3.x 키) | 재배포 |
| `observability/grafana/provisioning/` | 데이터소스(UID 고정), 대시보드 provider, 알림 | 재배포 |
| `observability/grafana/dashboards/<폴더>/*.json` | 대시보드. 하위 폴더 이름이 Grafana 폴더 | git pull 후 30초 안에 자동 반영 |

admin 계정(`GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD`)과 알림 webhook(`GRAFANA_ALERT_WEBHOOK_URL`)은
`secrets/env.<환경>.sops.env`에 있다. 운영 계정은 Jenkins 로그인·Basic Auth와 같은 값을 복사해 둔 것이다.
연동이 아니라 복사이므로 Jenkins 비밀번호를 바꿔도 Grafana는 따라오지 않는다. 계정은 Grafana 최초 기동 때만
적용된다. 이후 비밀번호는 Grafana 화면의 프로필 → Change password로 바꾸고, 기록을 맞추려면 SOPS 값도 고친다.
비밀번호를 잊었을 때만 VPS에서 `docker exec vps-grafana grafana cli admin reset-admin-password <새 비밀번호>`를 쓴다.

# 조회

로그는 Grafana Explore의 LogQL로 본다. `docker logs`는 관측 스택 자체가 죽었을 때만 쓴다.

```logql
{container="vps-nginx"} | json | status >= 500
{compose_project="vps-info"} |= "error"
{service_name="jenkins"} | ci_pipeline_id="vps-infra-pipeline" | ci_pipeline_run_number="24"
```

- 로그 레벨은 로그를 만드는 쪽이 쓴다. nginx는 access log에 HTTP 상태로 정한 `level`(5xx error, 4xx warn,
  나머지 info)을 쓰고, vps-info 서버는 pino 레벨을 이름(`"level":"info"`)으로 쓴다(vps-info
  `docs/conventions/logging.md`). Alloy는 로그 내용을 바꾸지 않는다. 형식 없는 텍스트 줄
  (vps-info collector·llm의 console.log)은 unknown이다.
- Jenkins 빌드 로그의 `ci_pipeline_id`, `ci_pipeline_run_number`, `trace_id`는 stream 라벨이 아니라
  structured metadata다. `{...}` 안에 쓰면 결과가 0줄이므로 `|` 뒤 필터로 쓴다.

- nginx 로그 줄의 `trace_id`와 Jenkins 빌드 로그의 `trace_id`는 Tempo 트레이스로 링크된다.
- Jenkins 파이프라인 트레이스는 `{resource.service.name="jenkins"}`이며 stage마다 span이 있다. root span은 빌드가 끝나야 닫힌다.
- Jenkins는 nginx가 전파한 `traceparent`를 이어받아 웹 요청도 span으로 낸다.
- 대시보드는 모두 공개 대시보드를 받아 우리 라벨·메트릭에 맞춘 것이다. 직접 만든 것은 없다.

| 대시보드 | 출처 | 맞춘 내용 |
|---|---|---|
| `Infra/Node Exporter Full` | grafana.com 1860 rev 45 | 없음 |
| `Infra/Docker monitoring` | grafana.com 15798 rev 16 | 데이터소스 자리표시자. 디스크 I/O 패널은 cAdvisor diskIO를 꺼서 비어 있다 |
| `Infra/NGINX Logs` | grafana/jsonnet-libs nginx-mixin `nginx-logs.json`(12559 기반) | 기본 변수 `container=vps-nginx`, geoip 패널 제거 |
| `Infra/Jenkins overview (OpenTelemetry)` | jenkinsci/opentelemetry-plugin `src/main/grafana/jenkins-overview.json` | `service_name`→`job` 라벨, 소요 시간 단위(ms→s)와 결과 라벨 이름, JVM 메트릭 이름, 큐 대기 시간 패널을 큐 길이 패널로 교체 |

- nginx access log는 Grafana NGINX 연동의 `json_analytics` 포맷에 `level`, `trace_id`, `span_id`만 덧붙인 것이다.
  필드 이름을 바꾸면 NGINX Logs 대시보드가 깨진다.

# 수집 규칙 바꾸기

수집 경로와 로그 가공은 모두 `observability/alloy/config.alloy` 한 파일에 있다. 컴포넌트를 선으로 잇는
구조이고(`forward_to`), 로그는 `loki.source.docker` → (가공) → `loki.write` 순서로 흐른다.

- **원칙: 로그 형식은 로그를 만드는 쪽에서 고친다.** 레벨, 필드 이름, 비밀값 제거는 앱 코드나 nginx 설정에서 한다.
  Alloy에서 고치면 인프라가 각 앱의 형식을 알아야 하고, `docker logs`로 볼 때는 고쳐지지 않는다.
- **Alloy에서 가공하는 경우:** 소스를 바꿀 수 없는 서드파티 로그만 다룬다. 시끄러운 로그 버리기, 새어 나온 비밀값 가리기 등이다.
  `loki.source.docker`와 `loki.write` 사이에 `loki.process`를 넣고 `stage.*`로 처리한다.
  - `stage.match`: 대상 고르기. selector에는 라벨만 쓴다. 라인 필터의 백틱 문자열은 파서가 받지 않는다.
  - `stage.regex`, `stage.json`: 값 뽑기
  - `stage.template`: 값 만들기. 없는 키를 `eq`로 비교하지 말고 `{{ with .x }}`로 감싼다.
  - `stage.structured_metadata`, `stage.labels`: 붙이기. 라벨은 stream 수를 늘리므로 값 종류가 적을 때만 쓴다.
  - `stage.drop`: 버리기
- **검증 순서:**
  1. `docker run --rm -v "$PWD/observability/alloy:/a:ro" grafana/alloy:<버전> fmt /a/config.alloy`로 문법을 본다.
  2. 로컬에서 `./scripts/deploy.sh observability`로 띄운다. 설정 평가 오류로 Alloy가 재시작을 반복하면 배포가 실패한다.
  3. 시험 로그를 내는 컨테이너를 몇 초 이상 띄워(너무 빨리 끝나면 수집 전에 사라진다) Loki 결과를 확인한다.
- 파일이 커지면 디렉터리로 나눌 수 있다. Alloy는 디렉터리를 주면 그 안의 `*.alloy`를 모두 읽는다.

# 알림

| 규칙 | 조건 |
|------|------|
| 디스크 사용률 85% 초과 | `/` 5분 지속 |
| 메모리 available 500MB 미만 | 2분 지속 |
| 서브도메인 응답 실패 | `probe_success` 0, 2분 지속. 대상: health, portal, jenkins, grafana, vps-info |
| Jenkins 큐 적체 | `jenkins_queue_buildable` > 0, 20분 지속 |

VPS 전체 다운은 외부 UptimeRobot이 `health.kkh-hub.tech`를 5분마다 확인한다(레포 밖 설정).

# 주의

- 컨테이너는 VPS 공개 IP로 hairpin하지 못한다. 공개 이름은 nginx의 `vps_proxy` alias로 해석되므로
  probe 대상 서브도메인을 늘리면 루트 `compose.yml`의 nginx alias에도 추가한다.
- 로컬 Docker(OrbStack) VM에는 containerd 소켓이 없어 컨테이너별 메트릭이 비고, 파일시스템 마운트포인트가 VPS와 다르다.
- Alloy는 privileged이고 `docker.sock`을 가진다. 호스트 root에 준하는 권한이다.
- Prometheus·Loki·Tempo는 `vps_observability` 네트워크에만 있어 다른 앱 컨테이너가 직접 닿지 않는다.

# 관련 개념

- [관측 스택을 VPS에 셀프호스팅하고 Alloy 하나로 수집한다](/adr/0016-self-hosted-observability.md)
- [외부 요청의 trace는 nginx가 시작한다](/adr/0017-nginx-starts-traces.md)
- [nginx 리버스 프록시](/services/nginx.md)
- [Jenkins 배포](/services/jenkins-deploy.md)
