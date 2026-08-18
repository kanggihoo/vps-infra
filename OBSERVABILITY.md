# 중앙 모니터링 설계 (검토 문서)

이 문서는 **kkh-hub.tech VPS 1대에 중앙 모니터링을 붙이는 방안**을 정리한 것이다.
아직 구현 전이며, 결정 근거와 수집 방식을 확정하는 것이 목적이다.

- 대상: Hostinger VPS 1대 (2코어 / 8GB / 100GB / 8TB)
- 전제: 공개 포트는 `80`, `443` 뿐. 새 컴포넌트도 호스트 포트를 열지 않는다.
- 결론 요약: **관측 백엔드는 Grafana Cloud 무료 티어**, VPS 안에는 **OTEL Collector만**,
  코드는 **기존 `vps-infra` 저장소에 통합**.

---

## 1. 왜 셀프호스팅하지 않는가

### 1-1. 메모리 예산

VPS 총 8GB. 현재 상주분:

| 컴포넌트 | 대략 RAM |
|----------|----------|
| nginx, certbot, whoami, portal | 100~200MB |
| postgres | 200~400MB |
| redis | 50~150MB |
| Jenkins (JVM, 유휴) | 500MB~1GB |
| Jenkins (빌드 중) | **+1~2GB** |

여기에 관측 스택을 셀프호스팅하면:

| 컴포넌트 | 대략 RAM | 비고 |
|----------|----------|------|
| Prometheus (15일 보존) | 1~2GB | 시리즈 수에 비례해 증가 |
| Loki (+ 인덱스) | 500MB~1GB | |
| Tempo | 300MB~1GB | |
| Grafana | 200MB | |
| **합계** | **2~4GB** | |

**빌드가 도는 순간 스왑을 치고, 2코어에서는 OOM으로 이어진다.**
스토리지(100GB)는 여유가 있지만 병목은 메모리와 CPU다.

### 1-2. 운영 부담

셀프호스팅은 리소스 외에도 다음을 직접 소유하게 된다.

- 보존 기간 / 리텐션 정책, 디스크 압박 대응
- Prometheus WAL 손상, Loki 인덱스 압축 실패 등 장애 대응
- 백업 (관측 데이터도 볼륨이다)
- Grafana를 외부에 노출한다면 서브도메인 + 인증 + 인증서까지 추가

**모니터링 스택 자체가 장애 원인이 되면 목적이 뒤집힌다.**
VPS 1대 규모에서는 관측 데이터를 밖에 두는 편이 명확히 유리하다.

### 1-3. Grafana Cloud 무료 티어

- 백엔드(Prometheus / Loki / Tempo / Grafana / Profiles)를 전부 관리형으로 제공
- VPS 안에는 **수집기 하나만** 남는다 → 상주 RAM **~320MB**
- Grafana 대시보드, 알림, 데이터소스 연결이 이미 세팅된 상태

> **한도는 계정 생성 후 실제 화면에서 확인할 것.**
> 무료 티어 수치(시리즈 수, 로그/트레이스 용량, 보존 기간)는 변경되므로
> 이 문서에 숫자를 고정하지 않는다. 다만 **시리즈 한도가 가장 먼저 걸린다**는
> 점은 아래 3-2에서 다룬다.

### 1-4. 트레이드오프 (알고 받아들이는 부분)

| 항목 | 내용 |
|------|------|
| 벤더 종속 | 대시보드와 알림 규칙이 Grafana Cloud에 남는다. 단, 수집기가 순수 OTEL Collector이므로 **파이프라인은 이식 가능**하다 (4-1 참조) |
| 데이터 외부 전송 | 메트릭/로그가 외부로 나간다. 로그에 민감 정보가 섞이지 않도록 앱 단에서 관리해야 한다 |
| 한도 초과 | 무료 한도를 넘으면 드롭 또는 과금. 3-2의 필터링이 필수인 이유 |
| 네트워크 의존 | Cloud 장애 시 관측이 끊긴다. Collector에 재시도/큐를 설정해 단기 장애는 흡수한다 |
| 대역폭 | 8TB 중 월 수십 GB 수준. **문제 없음** |

---

## 2. 배치: 별도 저장소 vs vps-infra 통합

### 결론: **`vps-infra` 안에 통합**

| 근거 | 설명 |
|------|------|
| 배포 대상이 동일 | 같은 VPS 1대. 저장소를 나누면 `.env`와 배포 스크립트가 두 벌이 된다 |
| 네트워크 공유 | Collector가 `vps_proxy`(Jenkins 스크레이프)와 `vps_data`(postgres/redis exporter) **둘 다** 필요하다. 저장소가 분리되면 `external: true` 네트워크 선언과 compose 프로젝트 간 기동 순서 의존이 생긴다 |
| nginx 설정 인접성 | 나중에 Alertmanager 등을 노출하려면 `nginx/conf.d/`에 파일을 추가해야 한다. 설정이 같은 저장소에 있어야 한다 |
| 규모 | 컨테이너 3개, 설정 파일 2개. 저장소를 나눠서 얻는 것이 없다 |
| 기존 패턴과 일치 | 이미 `compose.yml` + `jenkins/compose.yml`로 compose를 분리해 쓰고 있다. 같은 패턴을 따른다 |

### 디렉토리 구조

```txt
vps-infra/
  compose.yml                    # 기존: nginx, certbot, whoami, portal, postgres, redis
  jenkins/
    compose.yml                  # 기존
    Dockerfile                   # 플러그인 추가 지점 (4-3)
  observability/                 # 신규
    compose.yml                  # otel-collector, node-exporter, cadvisor
    otel-collector.yaml          # 파이프라인 설정
    .env.example                 # GRAFANA_CLOUD_* 자리표시자
  nginx/conf.d/                  # 필요 시 Alertmanager 등 추가
  INFRA.md                       # observability 섹션 추가 필요
  OBSERVABILITY.md               # 이 문서
```

**시크릿 취급**: Grafana Cloud API 토큰은 `observability/.env`에만 두고 커밋하지 않는다.
저장소 루트 `.gitignore`에 `.env`가 이미 등록되어 있음을 확인했다.
`.env.example`에는 키 이름만 남긴다.

---

## 3. 수집기 선택

### 3-1. OTEL Collector vs Grafana Alloy

두 후보를 검토했다. **Grafana Alloy는 OTEL Collector를 포크한 배포판**이라 기능은 대부분 겹친다.

| 항목 | OTEL Collector | Grafana Alloy |
|------|----------------|---------------|
| 메트릭 스크레이프 | `prometheus` receiver | `prometheus.scrape` |
| 트레이스 수신 | `otlp` receiver | 동일 |
| **Docker 컨테이너 로그** | `filelog`로 파일 tail. **컨테이너 이름이 안 붙는다** (경로에 ID만 있음) | `loki.source.docker`가 Docker API로 디스커버리 → **이름/compose 라벨 자동** |
| 설정 문법 | YAML | Alloy 고유 문법 (HCL 계열) |
| 벤더 중립성 | 높음 | Grafana 생태계 종속 |

Alloy의 유일한 실질 이점은 **Docker 로그 자동 라벨링**이다.

### 결론: **OTEL Collector**

로그 대상을 구체화하면 Alloy의 이점이 사라진다.

| 로그 대상 | 수집 방식 | 컨테이너 이름 문제 |
|-----------|-----------|-------------------|
| 앞으로 붙는 서비스 (자체 개발) | 앱에 OTEL SDK → OTLP push | 없음. `service.name`이 정확히 붙는다 |
| Jenkins | OpenTelemetry plugin → OTLP push | 없음. plugin이 `service.name`을 설정한다 |

**둘 다 Docker JSON 로그를 파일 tail 하지 않는다.**
서드파티 컨테이너가 Jenkins 하나뿐이고 그마저 plugin이 직접 push하므로,
Alloy를 추가할 근거가 없다. 벤더 중립성을 지키는 쪽을 택한다.

> 나중에 SDK를 못 넣는 서드파티 컨테이너가 여러 개로 늘어나면 이 결정을 재검토한다.
> 그 시점에는 `filelog` + 수제 ID→이름 매핑보다 Alloy를 로그 전용으로 하나 더
> 띄우는 편이 낫다 (Collector와 병행 가능).

### 3-2. cAdvisor 시리즈 폭발과 필터링

**이것이 무료 티어에서 가장 먼저 터지는 지점이다.**

시계열(series) 하나 = **메트릭 이름 + 라벨 조합 하나**. 무료 한도는 이 개수로 센다.
cAdvisor는 컨테이너마다 메트릭을 수백 개 내고, **라벨이 곱해진다.**

컨테이너 1개당 시리즈가 특히 많은 메트릭:

| 메트릭 | 라벨 | 컨테이너당 시리즈 |
|--------|------|------------------|
| `container_blkio_device_usage_total` | 디바이스 × operation(Read/Write/Sync/Async/Total) | 10~40 |
| `container_fs_*` | 파일시스템 디바이스마다 | 5~15 |
| `container_tasks_state` | `state=` sleeping/running/stopped/uninterruptible/iowaiting | 5 |
| `container_memory_failures_total` | `scope` × `failure_type` | 4 |
| `container_cpu_usage_seconds_total` | `cpu=cpu00, cpu01` | 코어 수만큼 |

기본 설정 기준 **컨테이너당 200~400 시리즈**. 컨테이너 8개면 **2k~3k**.

여기에 두 가지가 더 겹친다.

1. **Jenkins가 빌드마다 띄우는 임시 컨테이너**도 각각 시리즈를 만든다.
2. **컨테이너가 사라져도 시리즈는 보존 기간 동안 남는다.**

빌드가 잦으면 한도를 빠르게 소모한다. 그래서 필터링은 선택이 아니다.

#### 2단계로 줄인다

**① 소스에서 (cAdvisor 플래그)** — 만들지 않으면 전송·저장도 없다. 가장 효율적.

```yaml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:v0.49.1
  command:
    - --docker_only                    # 호스트 cgroup 제외, 컨테이너만
    - --store_container_labels=false   # compose 라벨이 전부 시리즈 라벨이 되는 것 방지
    - --disable_metrics=disk,diskIO,tcp,udp,percpu,sched,process,hugetlb,referenced_memory,cpu_topology,resctrl
```

| 플래그 | 효과 |
|--------|------|
| `--disable_metrics=diskIO,disk` | `container_blkio_*`, `container_fs_*` 제거. **절감 폭이 가장 크다** |
| `--disable_metrics=percpu` | CPU를 코어별로 쪼개지 않는다 |
| `--store_container_labels=false` | `com.docker.compose.*` 등이 시리즈 라벨이 되는 것을 막는다. 이걸 빼면 **라벨 값이 바뀔 때마다 새 시리즈가 생긴다** |
| `--docker_only` | 호스트 cgroup 계층 메트릭 제거 |

**② Collector에서 (`filter` processor)** — 허용 목록으로 확정한다.

```yaml
processors:
  filter/cadvisor:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - container_cpu_usage_seconds_total
          - container_memory_working_set_bytes
          - container_memory_usage_bytes
          - container_network_(receive|transmit)_bytes_total
          - container_fs_usage_bytes
          - container_last_seen
```

두 단계를 적용하면 **컨테이너당 6~10 시리즈**. 8개 컨테이너 기준 **~80 시리즈**.
(약 3000 → 약 80)

> **운영 규칙**: 배포 직후 Grafana Cloud의 사용량(usage) 화면에서 실제 시리즈 수를
> 확인하고 필터를 조정한다. 새 서비스를 붙일 때마다 같은 확인을 반복한다.

---

## 4. 신호별 수집 방식

### 4-1. 전체 데이터 경로

```
   ┌─────────────── VPS (Docker) ───────────────┐
   │                                             │
   │  node-exporter ──scrape──┐                  │
   │  cAdvisor ───────scrape──┤                  │
   │  Jenkins /prometheus ────┤                  │
   │  (postgres/redis exporter)┤                 │
   │                          ▼                  │
   │                  ┌───────────────┐          │
   │  Jenkins OTel ──▶│ OTEL Collector│──OTLP───▶│──▶ Grafana Cloud
   │  plugin  (push)  │   ~200MB      │  (TLS)   │    (Prometheus/Loki/Tempo)
   │  신규 앱 SDK ───▶│               │          │
   │          (push)  └───────────────┘          │
   └─────────────────────────────────────────────┘
                                                       Grafana Cloud 대시보드로 조회
```

**이식성**: 수집 파이프라인이 순수 OTEL 설정이므로, 백엔드를 바꿀 때는
`exporters` 블록의 엔드포인트만 교체하면 된다. receiver / processor는 그대로 쓴다.

### 4-2. 수집 대상 정리

| 소스 | 방식 | 신호 | 우선순위 |
|------|------|------|----------|
| 호스트 CPU / 메모리 / 디스크 / 로드 | node-exporter → Collector scrape | 메트릭 | **1차** |
| 컨테이너별 리소스 | cAdvisor → Collector scrape | 메트릭 | **1차** |
| Jenkins 인스턴스 상태 (큐, executor, JVM 힙) | Prometheus plugin → Collector scrape | 메트릭 | **1차** |
| Jenkins 파이프라인 (스테이지별 소요) | OpenTelemetry plugin → OTLP push | 트레이스 | **1차** |
| 신규 앱 | OTEL SDK → OTLP push | 메트릭 + 트레이스 + 로그 | 서비스 추가 시 |
| postgres / redis | exporter → Collector scrape | 메트릭 | 2차 |
| postgres slow query / deadlock | postgres 로그 설정 + `filelog` | 로그 | 필요 시 |
| Jenkins 빌드 로그 | OpenTelemetry plugin 로그 옵션 | 로그 | **초기에는 끔** (4-3) |
| 프로파일 | Pyroscope SDK | 프로파일 | **보류** (4-5) |

**Collector 재시작 내구성**: scrape는 Collector가 죽어도 재시작하면 이어진다(누적
카운터 기반). push 방식(OTLP)은 그 사이 데이터가 유실될 수 있으므로,
Collector에 `sending_queue`와 `retry_on_failure`를 설정해 Cloud 단기 장애를 흡수한다.

### 4-3. Jenkins — 플러그인 2개

Jenkins에는 별도 컨테이너를 추가하지 않는다. **플러그인만 설치**한다.

> **확인된 사실**: 현재 `jenkins/Dockerfile`에는 플러그인 설치 단계가 **없다**
> (Docker CLI 설치만 한다). `plugins.txt`도 없다. 즉 지금까지 플러그인은
> **Jenkins UI에서 수동 설치**해 왔고, 그 상태는 `jenkins-data` 볼륨에만 남아 있다.
>
> 이 문서의 플러그인 2개를 추가할 때 두 갈래가 있다.
>
> | 방식 | 장점 | 단점 |
> |------|------|------|
> | UI에서 수동 설치 | 즉시 가능, 기존 방식과 일치 | 볼륨을 잃으면 재현 불가. 코드에 기록이 없다 |
> | `Dockerfile`에 `plugins.txt` 추가 | 형상관리됨, 재현 가능 | 기존 수동 설치 플러그인 목록을 먼저 뽑아 `plugins.txt`에 옮겨야 한다 |
>
> **후자를 권장하되 별도 작업으로 분리한다.** 모니터링 도입과 플러그인 형상관리
> 전환을 한 번에 하면 문제 원인을 가리기 어렵다.
> 기존 목록은 Jenkins의 Script Console에서 뽑을 수 있다.
>
> ```groovy
> Jenkins.instance.pluginManager.plugins
>   .findAll { !it.isBundled() }
>   .collect { "${it.shortName}:${it.version}" }
>   .sort()
>   .each { println it }
> ```
>
> 전환 시 `Dockerfile`은 다음 형태가 된다.
>
> ```dockerfile
> COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
> RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt
> ```
>
> `USER jenkins`로 되돌린 **뒤에** 실행해야 한다 (현재 Dockerfile 마지막 줄).

#### ① `prometheus` (Prometheus metrics plugin) — scrape

- 엔드포인트: `http://jenkins:8080/prometheus/`
- Collector가 `vps_proxy` 내부에서 스크레이프한다

| 지표 | 용도 |
|------|------|
| `jenkins_queue_size_value`, `_blocked_`, `_stuck_` | **2코어라 큐 적체가 실제 장애 원인이다** |
| `jenkins_executor_count_value` / `_in_use_` | executor 포화도 |
| `vm_memory_heap_usage`, `vm_gc_*` | **Jenkins OOM 진단** |
| `jenkins_builds_success_build_count` / `_failed_` | 잡별 성공/실패 누적 |
| `jenkins_builds_last_build_duration_milliseconds` | 마지막 빌드 소요 |
| `jenkins_builds_last_build_result_ordinal` | 0=성공, 1=불안정, 2=실패 |
| `jenkins_node_*`, `jenkins_health_check_*` | 노드/자체 헬스체크 |

**인증**: 기본적으로 `Overall/Read` 권한이 필요하다.

**API 토큰 + Basic Auth로 확정한다. 익명 접근은 열지 않는다.**

`jenkins/README.md`의 초기 설정 절차 3번이 **"Disable anonymous read access and
user signup"** 을 명시하고 있다. 즉 익명 읽기를 끄는 것이 이 인프라의 기존 방침이다.
`/prometheus` 하나만 예외로 여는 것은 그 방침을 되돌리는 일이고,
Jenkins의 익명 권한은 경로 단위로 깔끔하게 좁혀지지 않는다.
Collector 설정 한 줄을 아끼려고 방침을 흔들 이유가 없다.

절차:

1. Jenkins에서 전용 사용자(예: `otel-scraper`)를 만들고 `Overall/Read`만 부여한다
2. 그 사용자의 API 토큰을 발급한다
3. 토큰을 `observability/.env`에 넣는다 (커밋하지 않는다)
4. Collector의 해당 scrape job에 Basic Auth를 설정한다 —
   사용자명은 Jenkins 사용자 ID, 비밀번호 자리에 **API 토큰**을 넣는다

관리자 계정의 토큰을 재사용하지 않는다. 스크레이프용 계정을 분리해야
토큰이 유출돼도 영향 범위가 읽기 권한으로 제한된다.

> `nginx/conf.d/jenkins.conf`는 확인만 한다. `/prometheus`를 외부로 노출할 필요는
> 없다 — Collector는 `vps_proxy` 내부에서 `http://jenkins:8080`으로 직접 도달한다.

**시리즈 주의**: 잡별로 라벨이 붙으므로 잡 개수에 비례해 늘어난다.
현재 규모에서는 무해하지만 잡이 수십 개가 되면 확인이 필요하다.

#### ② `opentelemetry` (OpenTelemetry plugin) — push

Jenkins가 직접 OTLP로 Collector에 보낸다. 스크레이프 불필요.

- 설정 위치: Jenkins 관리 → System → OpenTelemetry
- Endpoint: `http://otel-collector:4317`
- Authentication: No Authentication (내부 네트워크)

얻는 것:

- **파이프라인 실행이 트레이스로 온다.** 스테이지별 소요 시간이 스팬으로 나뉘므로
  `Jenkinsfile`의 어느 스테이지가 느린지 바로 보인다
- `service.name=jenkins`가 자동 설정되어 컨테이너 이름 매핑 문제가 없다
- 빌드 로그도 OTLP로 보낼 수 있다 (아래)

**빌드 로그 전송은 초기에 끈다.**

| 근거 | 설명 |
|------|------|
| 용량 | 빌드 로그 전량이 Cloud 로그로 간다. 빌드가 잦으면 무료 로그 한도를 빠르게 소모한다 |
| 대체 수단이 있다 | 빌드 로그는 Jenkins UI에서 그대로 볼 수 있다 |
| 알림은 분리되어 있다 | 빌드 실패 알림은 기존 `jenkins-build-notifier` 프로젝트가 담당한다 |
| 트레이스로 충분하다 | "어느 스테이지가 느린가"는 트레이스가 답한다 |

필요해지면 그때 켠다.

#### 두 플러그인이 겹치지 않는 이유

`opentelemetry` plugin도 `ci.pipeline.run.*` 메트릭을 일부 내보내지만,
**큐 / executor / JVM 힙 지표는 `prometheus` plugin이 훨씬 풍부하다.**
2코어 VPS에서 실제 장애 원인이 큐 적체와 JVM 힙이므로 둘 다 설치할 값어치가 있다.

### 4-4. postgres / redis

#### exporter는 메트릭 전용이다

`postgres_exporter`, `redis_exporter`는 Prometheus exporter이므로 **메트릭만** 낸다.
로그도 트레이스도 내지 않는다.

#### 로그 — 필요하지만 우선순위가 낮다

postgres 로그에서 가치가 있는 항목:

| 항목 | 설정 | 가치 |
|------|------|------|
| slow query | `log_min_duration_statement=1000` | 높음 |
| deadlock | `log_lock_waits=on` | 높음 |
| connection 폭주 | `log_connections=on` | 중간 (메트릭으로도 보인다) |
| 체크포인트 | `log_checkpoints=on` | 중간 |

그런데 **상당 부분이 메트릭으로 대체된다.**

- `pg_stat_statements` 확장을 켜면 `postgres_exporter`가 **쿼리별 평균/최대
  실행시간을 메트릭으로** 낸다. 로그 파싱보다 낫다 (집계된 형태, 시리즈 소수)
- deadlock 발생 횟수는 `pg_stat_database_deadlocks` 카운터로 온다

즉 **"몇 번 일어났나"는 메트릭, "어떤 쿼리였나"는 로그**의 역할이다.

**권장**: exporter 메트릭 + `pg_stat_statements`부터 시작한다.
로그는 실제로 문제를 겪은 뒤에 붙인다.
redis 로그는 가치가 거의 없다 (재시작/persistence 이벤트 위주) — `redis_exporter`로 충분하다.

#### 트레이싱 — DB에 붙이는 것이 아니라 앱에 붙인다

**이 부분이 개념적으로 혼동하기 쉬운 지점이다.**
DB 쿼리 트레이스는 DB가 만드는 것이 아니라 **앱의 OTEL SDK가 만든다.**

앱에 SDK를 넣으면 이런 형태가 된다.

```
[span] POST /api/orders                120ms
  ├─[span] db.query SELECT users        15ms   ← DB 스팬
  ├─[span] db.query INSERT orders       80ms
  └─[span] redis.GET session             2ms
```

DB 클라이언트 라이브러리(psycopg, JDBC, node-postgres 등)에 OTEL instrumentation을
붙이면 자동 생성된다. **postgres 쪽에는 아무 설정도 하지 않는다.**

postgres 자체가 트레이스를 내보내는 방법은 사실상 없다
(`pg_tracing` 같은 실험적 확장이 있으나 프로덕션용이 아니다).

| | postgres / redis | 방법 |
|---|---|---|
| 메트릭 | 필요 | exporter |
| 로그 | 나중에 | postgres 설정 + `filelog` |
| 트레이스 | **DB에 붙이지 않는다** | 앱 SDK가 만든다 |

### 4-5. 프로파일 (Pyroscope) — 보류

**4번째 신호로 실재한다.** Grafana가 Pyroscope를 인수해 Grafana Cloud Profiles로
통합했고 무료 티어에도 포함된다 (한도는 계정에서 확인).
OTLP에도 profiles 시그널이 들어오고 있으나 아직 성숙 중이어서,
현재는 **Pyroscope SDK를 앱에 직접 넣는 방식**이 실용적이다.

다른 신호가 답하지 못하는 것을 답한다.

| 신호 | 답하는 질문 |
|------|-------------|
| 메트릭 | "CPU가 80%다" |
| 트레이스 | "이 요청이 500ms 걸렸다" |
| **프로파일** | **"그 500ms 중 340ms가 `json.Marshal` 안에서 탔다"** — 함수 단위 |

#### 지금 넣지 않는 이유

| 근거 | 설명 |
|------|------|
| 대상 앱이 없다 | 앱 계측이 필수인데, 붙일 서비스가 아직 없다 |
| 오버헤드 | 연속 CPU 프로파일링은 앱 CPU를 2~5% 쓴다. **2코어에서 무시할 수 없다** |
| 순서 문제 | 프로파일링은 문제를 좁힌 **다음** 쓰는 도구다. 메트릭/트레이스도 없는 상태에서는 볼 것이 없다 |
| Jenkins에는 무의미 | Java라 async-profiler 기반으로 붙일 수는 있으나, Jenkins 내부 코드는 고칠 수 없다 |

**넣을 시점**: 신규 서비스가 실제로 CPU/메모리 문제를 보이고,
트레이스로 "이 엔드포인트가 느리다"까지는 알았으나 "왜"를 모를 때.

### 4-6. 신호 4종 요약

| 신호 | 1차 도입 | 나중 |
|------|----------|------|
| 메트릭 | node-exporter, cAdvisor, Jenkins `prometheus` plugin | postgres / redis exporter |
| 트레이스 | Jenkins `opentelemetry` plugin, 신규 앱 SDK | — |
| 로그 | 신규 앱 SDK만 | postgres slow query, Jenkins 빌드 로그 |
| 프로파일 | 없음 | 성능 문제 발생 시 Pyroscope SDK |

---

## 5. 리소스 예산

| 컴포넌트 | 대략 RAM |
|----------|----------|
| otel-collector | ~200MB |
| node-exporter | ~20MB |
| cAdvisor | ~100MB |
| **합계** | **~320MB** |

8GB 중 320MB. 셀프호스팅(2~4GB) 대비 명확한 이점이다.

**CPU**: 스크레이프 주기를 너무 짧게 잡지 않는다. 2코어이므로 `30s`~`60s`로
시작하고, 필요할 때만 줄인다. 15s 미만은 시리즈 수 대비 이득이 적다.

---

## 6. 결정해야 할 사항

### 6-1. cAdvisor의 권한 (판단 필요)

cAdvisor가 컨테이너 메트릭을 읽으려면 `/sys`, `/var/lib/docker`(읽기 전용),
그리고 보통 `/var/run/docker.sock`을 마운트해야 한다.
**호스트 자원에 광범위하게 접근하는 컨테이너가 하나 늘어난다.**

| 선택 | 결과 |
|------|------|
| cAdvisor 포함 | 컨테이너별 메모리/CPU 추적 가능. **원래 목적에 부합** |
| node-exporter만 | 호스트 전체 지표만. 어느 컨테이너가 메모리를 먹는지 알 수 없다 |

"어느 서비스가 메모리를 먹는가"를 알려는 것이 목적이므로 **cAdvisor 포함을 권장**한다.
다만 `docker.sock`은 읽기 전용으로 마운트하고, 호스트 포트는 열지 않는다.

### 6-2. Jenkins 플러그인 형상관리 전환 (판단 필요)

현재 플러그인은 UI 수동 설치 상태이고 `jenkins-data` 볼륨에만 존재한다.
`plugins.txt` + `jenkins-plugin-cli`로 전환할지, 이번에도 수동 설치할지 결정한다.
전환을 권장하되 모니터링 도입과 **분리된 작업**으로 진행한다. 4-3 참조.

> Jenkins `/prometheus` 인증은 **결정 완료** — API 토큰 + Basic Auth, 전용 계정.
> `jenkins/README.md`의 익명 읽기 차단 방침을 유지한다. 4-3 참조.

### 6-3. `service.name` 명명 규칙 (미정)

신규 서비스에 SDK를 넣을 때 `service.name`을 무엇으로 할지 규칙을 먼저 정해야 한다.
나중에 바꾸면 대시보드와 알림이 전부 깨진다.
서브도메인과 일치시키는 방안(`portal`, `notes`, `myapp`)을 검토한다.

---

## 7. 작업 순서 (구현 시)

1. Grafana Cloud 계정 생성 → OTLP 엔드포인트 + API 토큰 발급, **무료 한도 실제 수치 확인**
2. `observability/compose.yml`, `otel-collector.yaml`, `.env.example` 작성
   - `.env`는 커밋하지 않는다
   - Collector에 `sending_queue` / `retry_on_failure` 설정
3. node-exporter + cAdvisor만 먼저 기동 → 호스트/컨테이너 메트릭 도달 확인
4. **Grafana Cloud 사용량 화면에서 시리즈 수 확인 → 필터 조정** (3-2)
5. Jenkins 플러그인 2개 설치 (`prometheus`, `opentelemetry`)
   - **`Dockerfile`에 플러그인 설치 단계가 없다.** UI 수동 설치 또는
     `plugins.txt` 전환 중 선택 (6-2)
   - `otel-scraper` 전용 계정 + API 토큰 발급 → `observability/.env` (4-3)
   - 빌드 로그 전송은 끈 상태로 시작
6. `service.name` 명명 규칙 확정 (6-3)
7. 신규 서비스 추가 시 OTEL SDK 적용
8. 최소 알림 규칙 설정 — 디스크 사용률, 메모리 여유, Jenkins 큐 적체, 서비스 down
9. `INFRA.md`에 observability 섹션 추가 (1-2 도메인 표, 네트워크 구조도 갱신)
10. (2차) postgres / redis exporter + `pg_stat_statements`

---

## 8. 재검토 조건

다음 상황이 되면 이 문서의 결정을 다시 본다.

| 조건 | 재검토 대상 |
|------|-------------|
| SDK를 넣을 수 없는 서드파티 컨테이너가 여러 개로 늘어남 | 3-1 (Alloy 병행) |
| 무료 한도를 반복적으로 초과 | 1-3 (유료 전환 vs 셀프호스팅 vs 수집 축소) |
| VPS를 2대 이상으로 확장 | 2 (별도 저장소 분리, Collector 계층화) |
| 데이터 외부 전송이 제약이 됨 | 1-4 (셀프호스팅 재검토) |
| 성능 병목을 트레이스로 좁혔으나 원인 불명 | 4-5 (Pyroscope 도입) |

---

## 관련 문서

- `INFRA.md` — 인프라 현황 및 신규 서비스 추가 가이드
- `README.md` — 저장소 개요
- `jenkins/README.md` — Jenkins 초기 설정
- `.okf/environments/hostinger-vps.md` — VPS 환경 메타데이터
- `.okf/runbooks/failure-diagnosis.md` — 장애 진단 런북
