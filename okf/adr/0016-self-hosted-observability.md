---
type: Decision
title: 관측 스택을 VPS에 셀프호스팅하고 Alloy 하나로 수집한다
description: Grafana·Prometheus·Loki·Tempo를 VPS의 별도 Compose project로 띄우고, 수집은 Grafana Alloy 컨테이너 하나가 맡는다. Grafana Cloud 방안(OBSERVABILITY.md)을 대체한다.
tags: [observability, grafana, prometheus, loki, tempo, alloy, monitoring]
timestamp: 2026-10-08T00:00:00+09:00
---

# 결정

VPS 안에 Grafana 기반 관측 스택을 셀프호스팅한다. 상주 컨테이너는 5개다.

```txt
observability/compose.yml  (별도 Compose project, vps_proxy·vps_data external)
  alloy       수집 전부 담당
  prometheus  메트릭 저장 (remote-write 수신만, 스스로 scrape하지 않는다)
  loki        로그 저장
  tempo       트레이스 저장
  grafana     조회·알림, grafana.<도메인>으로만 외부 노출
```

Alloy 하나가 아래를 모두 처리한다. node-exporter, cAdvisor, blackbox를 별도 컨테이너로 띄우지 않는다.

```txt
prometheus.exporter.unix      호스트 CPU·메모리·디스크·로드      ─┐
prometheus.exporter.cadvisor  컨테이너별 자원                    │
prometheus.exporter.blackbox  서브도메인 생존 probe              ├─ remote_write → Prometheus
otelcol.receiver.otlp         Jenkins 메트릭(OTel plugin)         ─┘
loki.source.docker            모든 컨테이너 stdout (이름·compose 라벨 자동) → Loki
otelcol.receiver.otlp         nginx·Jenkins 트레이스 → Tempo, Jenkins 빌드 로그 → Loki
```

1차 범위는 호스트 자원, 컨테이너 자원, 서브도메인 생존, 전체 컨테이너 로그, Jenkins(메트릭·파이프라인
트레이스·빌드 로그)다. 메모리 상한 초기값은 Alloy·Prometheus·Grafana 512m, Loki·Tempo 384m다.
2026-10-08 VPS 첫 배포 직후 실측은 Alloy 310MiB, Grafana 397MiB, Loki 175MiB, Tempo 95MiB,
Prometheus 97MiB로 합계 약 1.07GiB이고, 호스트 available은 5.4GB였다. postgres/redis exporter와 vps-info 앱 계측은 범위 밖이다.

| 항목 | 값 |
|------|----|
| scrape 주기 | 30초 |
| Prometheus 보존 | 15일, `retention.size` 5GB |
| Loki 보존 | 7일, compactor 삭제 활성화 |
| Tempo 보존 | 72시간 |
| 메모리 | 모든 컨테이너에 `mem_limit`. 초기값은 구현 시 실측으로 정한다 |
| Grafana 인증 | Grafana 자체 로그인. admin 계정은 SOPS env, 익명 접근·가입 차단 |
| 외부 노출 | Grafana만 nginx 템플릿 1개로. Prometheus·Loki·Tempo·Alloy UI는 노출하지 않는다 |

Grafana 설정은 레포 파일로 provisioning한다. 데이터소스, 대시보드 JSON, 알림(contact point와 규칙)
모두 해당한다. 디렉터리를 bind mount하므로 git pull만으로 Grafana가 변경을 읽는다. 이미지에 넣지 않는다.

알림은 Grafana alerting이 Mattermost(Jenkins 빌드 알림과 같은 webhook)로 보낸다. Grafana에는
Mattermost 전용 연동이 없어 slack 타입에 incoming webhook URL만 준다. 1차 규칙은 4개다.

- 디스크 사용률 85% 초과
- 메모리 available 500MB 미만
- 서브도메인 probe 실패
- Jenkins 큐 적체

VPS 전체가 죽는 경우는 관측 스택도 함께 죽으므로 외부 UptimeRobot(무료, 5분 간격)이
`health.<도메인>`을 감시한다. 이 설정은 레포 밖에 있다.

Jenkins 빌드 콘솔 로그는 OTel plugin의 로그 전송으로 Loki에 보내고, Jenkins도 자기 사본을 유지한다.
Jenkins가 로그를 Loki에서만 읽는 모드는 쓰지 않는다. Loki 장애가 Jenkins 빌드 로그 유실이 되면 안 된다.

# 이유

**Grafana Cloud(기존 `OBSERVABILITY.md` 결론)를 대체한다.** 그 문서는 셀프호스팅이 RAM 2~4GB를 먹어
빌드 중 OOM으로 이어진다고 봤다. 2026-10-07 실측은 다르다.

```txt
메모리  7.9GB 중 1.9GB 사용, available 6.0GB, swap 없음
        Jenkins 846MiB(상한 2g), 나머지 컨테이너 합계 약 400MiB
CPU     2코어
디스크  96GB 중 82GB 여유
```

컨테이너 10개, 시리즈 수천 개 규모에서 단일 바이너리 모드에 상한을 걸면 스택 전체가 약 0.9~1.6GB다.
여유 안에 들어간다. [ADR 0006](/adr/0006-jenkins-builds-on-vps.md)이 Jenkins를 VPS에서 빌드하게 한 것과
같은 논리로, 관측 스택 운영 자체가 학습 대상이다. 관측 데이터가 외부로 나가지 않는다는 점도 이점이다.

**Alloy 하나로 수집한다.** 기존 문서는 OTEL Collector를 골랐다. 로그를 앱 SDK push로만 받는다는 전제였다.
실제로는 vps-info와 nginx 모두 stdout으로만 로그를 낸다. 그래서 Docker 로그 수집이 필수다. Alloy의
`loki.source.docker`는 컨테이너 이름과 compose 라벨을 자동으로 붙이고, exporter를 내장해 컨테이너
2개(약 100MB)를 줄인다.

**별도 Compose project로 둔다.** 인프라 배포(`docker compose up -d`)가 관측 스택을 재생성하면 배포 중
장애를 관측할 수 없다. Jenkins를 분리한 것과 같은 논리다
([ADR 0007](/adr/0007-per-project-compose.md)). 별도 레포는 같은 VPS, SOPS key, nginx 템플릿을 공유하므로
얻는 것이 없다.

**Grafana 설정을 파일로 관리한다.** 볼륨을 잃으면 UI에서 만든 데이터소스, 대시보드, 알림 규칙을
재현할 수 없다. [ADR 0009](/adr/0009-jenkins-config-as-code.md)(JCasC)와 같은 이유다.

# 결과

- Alloy에 `/proc`, `/sys`, `/`(ro), `/var/lib/docker`(ro), `docker.sock`이 붙는다. `docker.sock`은 `:ro`여도
  Docker API 전체에 접근할 수 있어 호스트 root에 가깝다. Jenkins와 `tools`가 이미 같은 권한이라 새 위험
  등급은 아니다.
- cAdvisor는 시리즈 폭발을 막아야 한다. 내장 컴포넌트에서 아래를 적용하고, 메트릭 이름을 허용 목록으로
  relabel한다. 기본 설정은 컨테이너당 200~400 시리즈이고, 필터 후 6~10개다.
  - `docker_only`
  - `store_container_labels=false` (빼면 라벨 값이 바뀔 때마다 새 시리즈가 생긴다)
  - `disabled_metrics`에 disk, diskIO, percpu, tcp, udp, sched, process 등
- Jenkins는 이미지 재빌드가 필요하다. `plugins.txt`에 `opentelemetry` 하나만 추가한다. 이 plugin이 트레이스·
  빌드 로그와 함께 Jenkins 메트릭(큐, executor, JVM)도 OTLP로 보내므로 `prometheus` plugin과 그 scrape 전용
  계정은 두지 않는다. 계정을 두면 같은 비밀번호를 `jenkins/.env`와 SOPS 양쪽에 맞춰야 한다. plugin은 Jenkins JVM
  안에서 돌아 기존 상한(`mem_limit` 2g, heap 1g) 안의 여유를 쓴다. 설치 후 heap을 실측한다.
- 컨테이너는 VPS 공개 IP로 자기 자신에 붙지 못한다(hairpin, 공개 IP와 host-gateway 모두 타임아웃, 2026-10-08 확인).
  그래서 nginx가 `vps_proxy`에서 공개 이름(`health.<도메인>` 등)을 alias로 갖고, Alloy probe는 실제 인증서와 SNI로
  nginx를 거친다. Basic Auth 뒤의 vps-info는 nginx 앞에서 401이 나므로 `vps-info-app:8000/api/health`를 직접 본다.
- Docker 29의 cAdvisor는 containerd 소켓으로 컨테이너를 찾으므로 `/run/containerd`도 마운트한다. 또 cgroup v2에서
  Alloy가 다른 컨테이너의 cgroup을 보려면 `cgroup: host`가 필요하다. privileged만으로는 루트 cgroup 하나만 보인다. 로컬
  Docker(OrbStack) VM에는 이 소켓이 없어 로컬에서는 컨테이너별 메트릭과 `/` 파일시스템이 보이지 않는다.
- Prometheus, Loki, Tempo는 내부 네트워크 `vps_observability`에만 둔다. `vps_proxy`의 앱은 저장소에 직접 닿지 않는다.
  Alloy와 Grafana만 두 네트워크에 붙는다.
- nginx는 `1.31.4-alpine-otel` 이미지로 바꾸고 로그를 JSON으로 바꾼다. 트레이스 규칙은
  [ADR 0017](/adr/0017-nginx-starts-traces.md)을 따른다.
- `grafana.kkh-hub.tech` DNS A 레코드를 추가했고, `secrets/env.prod.sops.env`의 `CHALLENGE_DOMAINS`에 넣었다.
  인증서는 배포 시 `deploy.sh`가 `--expand`한다.
- 배포 대상에 `observability`를 추가했다. `observability/`만 바뀌면 그 project만, `all`이면 인프라 뒤에 함께 올린다.
  설정 파일은 bind mount라 내용만 바뀌면 compose가 재생성하지 않으므로, `deploy.sh`가 서비스별 설정 checksum을
  환경변수로 넘겨 바뀐 서비스만 재생성한다.
- 로컬 Docker에서도 같은 compose를 띄운다. host 메트릭은 Docker VM 수치다.
- 로그 조회는 Grafana Explore의 LogQL이 기본이다. 관측 스택 자체가 죽었을 때만 `docker logs`를 쓴다.
- 트레이스는 span이 끝날 때 전송된다. Jenkins 파이프라인의 root span은 빌드가 끝나야 닫히므로,
  진행 중인 빌드는 끝난 stage만 보인다.

# 나중에 다룰 것

- **postgres/redis**: exporter와 `pg_stat_statements`. "몇 번 일어났나"는 메트릭으로, "어떤 쿼리였나"는
  slow query 로그로 본다. redis 로그는 가치가 낮아 exporter로 충분하다.
- **DB 트레이스**: DB가 만들지 않는다. 앱의 DB 클라이언트 계측(`pg` 등)이 span을 만든다. postgres 쪽에는
  설정이 없다.
- **프로파일(Pyroscope)**: 트레이스로 느린 구간을 좁혔는데 원인을 모를 때 도입한다. 2코어에서 연속
  프로파일링 오버헤드(2~5%)를 무시할 수 없다.

# 재검토 조건

| 조건 | 재검토 대상 |
|------|-------------|
| 빌드 중 메모리 available이 반복해서 500MB 아래로 떨어짐 | 셀프호스팅 유지, 보존 축소, Cloud 전환 |
| 디스크가 관측 데이터로 압박 | 보존 기간과 크기 상한 |
| VPS가 2대 이상 | 관측 스택 분리, 수집 계층화 |

# 관련 개념

- [외부 요청의 trace는 nginx가 시작한다](/adr/0017-nginx-starts-traces.md)
- [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md)
- [프로젝트별 독립 Compose](/adr/0007-per-project-compose.md)
- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [빌드 결과를 Shared Library로 Mattermost에 알린다](/adr/0012-mattermost-build-notification.md)
- [Hostinger VPS](/environments/hostinger-vps.md)
