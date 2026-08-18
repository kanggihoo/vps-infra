# 인프라 현황 및 신규 서비스 추가 가이드

이 문서는 **kkh-hub.tech VPS에 새 서비스를 하나 더 붙일 때** 필요한 정보를 모아둔
것이다. 앞부분은 현재 상태 레퍼런스, 뒷부분은 그대로 따라 하면 되는 체크리스트다.

- 대상: Hostinger VPS 1대, Docker Compose 기반
- 진입점: nginx (80/443 단독 점유)
- CI/CD: Jenkins (VPS 내부에서 실행)
- 라우팅: `*.kkh-hub.tech` 서브도메인 기반

---

## 1. 현재 상태 레퍼런스

### 1-1. 기본 정보

| 항목 | 값 |
|------|-----|
| Provider | Hostinger VPS |
| Public IP | `187.77.114.68` |
| Domain | `kkh-hub.tech` |
| CPU / 특성 | **2 코어** (빌드 동시성 설정 시 중요) |
| SSH | `ssh vps` (user `kkh`, docker 그룹 소속) |
| 인프라 저장소 경로 | `/opt/vps-infra` |
| 공개 포트 | `80`, `443` **만** |

> 공개 포트가 80/443뿐이라는 점이 핵심이다. 새 서비스는 자기 포트를 호스트에
> 노출하지 않고, nginx가 내부 네트워크로 프록시해 주는 방식으로만 외부에 나간다.

### 1-2. 도메인 → 서비스 매핑

| 도메인 | 서비스 | 내부 주소 | 인증 | 성격 |
|--------|--------|-----------|------|------|
| `health.kkh-hub.tech` | whoami | `http://whoami:80` | 없음 | 헬스체크용 |
| `portal.kkh-hub.tech` | portal | `http://portal:8080` | 없음 | 대시보드 |
| `jenkins.kkh-hub.tech` | jenkins | `http://jenkins:8080` | Jenkins 자체 로그인 | CI/CD |
| `notes.kkh-hub.tech` | (정적 파일) | `/var/www/notes` | Basic Auth | Quartz 노트 |
| `kkh-hub.tech` | — | — | — | 80에서 리다이렉트만 |

`postgres`, `redis`는 `data` 네트워크에만 있고 nginx와 무관하다. 외부 노출 없음.

### 1-3. 네트워크 구조

```
                    인터넷
                      │
              :80 / :443 (호스트)
                      │
              ┌───────▼────────┐
              │   vps-nginx    │   ← 유일한 진입점
              └───────┬────────┘
                      │
        ┌─────────────┴──────────────┐
        │   vps_proxy (Docker 네트워크)  │
        └─┬────────┬────────┬─────────┘
          │        │        │
      whoami   portal   jenkins        ... 새 서비스는 여기에 붙는다
                                        (+ nginx가 읽는 정적 파일 경로)

        ┌────────────────────────────┐
        │   vps_data (Docker 네트워크)  │   ← nginx에서 접근 불가
        └─┬──────────┬───────────────┘
          │          │
      postgres     redis
```

**핵심 규칙 두 가지:**

1. `vps_proxy`에 붙은 컨테이너끼리는 **컨테이너 이름이 곧 호스트명**이다.
   Docker 내장 DNS(`127.0.0.11`)가 이름을 컨테이너 IP로 풀어준다.
   그래서 nginx가 `proxy_pass http://portal:8080`이라고 쓸 수 있다.
2. 새 서비스는 `ports:`로 호스트 포트를 열 필요가 **없다**. 오히려 열면 안 된다.
   `expose`조차 필요 없고, 같은 네트워크에만 있으면 nginx가 도달한다.

### 1-4. Compose 프로젝트 구성

인프라는 **compose 파일 2개**로 나뉜다.

| 파일 | 내용 | 네트워크 |
|------|------|----------|
| `/opt/vps-infra/compose.yml` | nginx, certbot, whoami, portal, postgres, redis | `vps_proxy`를 **생성** |
| `/opt/vps-infra/jenkins/compose.yml` | jenkins | `vps_proxy`를 `external: true`로 **참조** |

Jenkins가 분리된 이유는, Jenkins가 자기 자신을 재시작하는 파이프라인을 돌리면
빌드 도중 자기 발밑이 사라지기 때문이다. 별도 프로젝트로 두면 `vps-infra` 배포가
Jenkins를 건드리지 않는다.

새 서비스는 특별한 이유가 없으면 **루트 `compose.yml`에 추가**한다.
독립적으로 재배포해야 하거나 다른 사람과 공유한다면 Jenkins처럼 별도 디렉터리 +
`external: true` 패턴을 쓴다.

### 1-5. 볼륨

| 이름 | 실제 이름 | 용도 |
|------|-----------|------|
| `certbot-etc` | `vps_certbot_etc` | 인증서 (`/etc/letsencrypt`) |
| `certbot-www` | `vps_certbot_www` | ACME challenge webroot |
| `postgres-data` | `vps_postgres_data` | DB 데이터 |
| `redis-data` | `vps_redis_data` | Redis AOF |
| `jenkins-data` | `vps_jenkins_data` | Jenkins 홈 |

호스트 바인드 마운트 경로:

| 호스트 경로 | 용도 |
|-------------|------|
| `/opt/vps-infra` | 인프라 저장소. Jenkins에도 같은 경로로 마운트 |
| `/opt/quartz-build` | Quartz 빌드 작업 폴더 |
| `/opt/quartz-site` | Quartz 산출물. nginx가 `/var/www/notes`로 읽음 |
| `/opt/nginx-auth/notes.htpasswd` | Basic Auth 비밀번호 파일 (Git 미포함) |

### 1-6. TLS 인증서

**SAN 인증서 1장**으로 전 도메인을 커버한다.

- 경로: `/etc/letsencrypt/live/kkh-hub.tech/{fullchain,privkey}.pem`
- 포함 도메인: `kkh-hub.tech`, `portal`, `health`, `jenkins`, `notes`
- 만료: 2026-11-07 (certbot 컨테이너가 12시간마다 자동 갱신)

모든 `*.conf`가 **같은 경로**를 참조하므로, 새 도메인을 추가할 때는
새 인증서를 발급받는 게 아니라 **기존 인증서에 도메인을 덧붙인다**(`--expand`).

발급 방식은 HTTP-01 webroot다. certbot이 `/var/www/certbot`에 챌린지 파일을 쓰고,
nginx의 `00-http-challenge.conf`가 그걸 서빙한다. 이 파일에 **새 도메인의
`server_name`을 미리 추가해 두지 않으면 발급이 실패**한다. (2-3 참고)

### 1-7. nginx 설정 파일 구조

```
/opt/vps-infra/nginx/
├── nginx.conf              # 최상위. 공통 설정 + include만. 라우팅 없음
└── conf.d/
    ├── 00-http-challenge.conf   # :80 — ACME 챌린지 + HTTPS 리다이렉트
    ├── health.conf              # :443 health.kkh-hub.tech
    ├── portal.conf              # :443 portal.kkh-hub.tech
    ├── jenkins.conf             # :443 jenkins.kkh-hub.tech
    └── notes.conf               # :443 notes.kkh-hub.tech (정적 + Basic Auth)
```

`nginx.conf`의 `include /etc/nginx/conf.d/*.conf;`가 `conf.d/`의 모든 파일을
알파벳 순으로 읽어 들인다. **서비스 1개 = conf 파일 1개**가 이 저장소의 규칙이다.

`conf.d/`는 `:ro`(읽기 전용)로 마운트되므로, 설정을 바꾸려면
호스트의 `/opt/vps-infra/nginx/`를 수정하고 nginx를 reload한다.

### 1-8. Jenkins

| 항목 | 값 |
|------|-----|
| URL | `https://jenkins.kkh-hub.tech` |
| 웹훅 엔드포인트 | `https://jenkins.kkh-hub.tech/github-webhook/` |
| 등록된 자격증명 | `github-pat` (GitHub PAT, `repo` 스코프) |
| Docker 접근 | `/var/run/docker.sock` 마운트 + `group_add: DOCKER_GID` |

Jenkins 컨테이너 안에는 Docker **CLI만** 있고 데몬은 없다. 소켓을 통해 호스트
데몬에 명령을 보내는 구조라, 파이프라인이 `docker run`을 하면 그 컨테이너는
Jenkins의 형제로 호스트에 뜬다. **그래서 `-v` 경로는 항상 호스트 기준**이다.
(`/opt/quartz-build`를 Jenkins에도 같은 경로로 마운트한 이유가 이것이다.)

⚠️ **Jenkins GitHub 플러그인 제약**: 웹훅을 보낸 저장소와 Job의 SCM URL이
일치해야만 빌드가 트리거된다. 그래서 Quartz의 `Jenkinsfile`은 `vps-infra`가 아니라
`quartz-site-private` 저장소에 있다. 새 서비스도 마찬가지로,
**Jenkinsfile은 그 서비스의 소스 저장소에 두는 것이 기본**이다.

### 1-9. 현재 배포 파이프라인 2종

**(A) 인프라 자체** — `vps-infra` push → Jenkins → `git pull` + `scripts/deploy.sh`

**(B) Quartz 노트** — 참고용 실제 사례:

```
옵시디언 노트 수정 → obsidian 저장소 push
   ↓ GitHub Actions (GitHub에서 실행, content/ 동기화)
quartz-site-private 커밋
   ↓ webhook → nginx:443 → jenkins:8080
Jenkins quartz-deploy Job (VPS에서 실행)
   Checkout → Build(node:22-slim 컨테이너) → Deploy(/opt/quartz-site) → Verify
   ↓
nginx가 정적 서빙
```

빌드 소요 약 3분(문서 2,762개). VPS가 2코어라 `--concurrency 2`로 맞춰 둔 상태.

---

## 2. 신규 서비스 추가 가이드

`myapp.kkh-hub.tech`에 웹 서비스를 붙이는 경우를 예로 든다.
**순서를 지켜야 한다.** 특히 2-3(인증서)은 2-4(conf 작성)보다 먼저다.

### 2-1. DNS A 레코드 추가

도메인 관리 콘솔에서:

```txt
A    myapp    187.77.114.68
```

전파 확인:

```bash
dig +short myapp.kkh-hub.tech
# 187.77.114.68 이 나와야 함
```

> 이게 안 되면 인증서 발급이 반드시 실패한다. Let's Encrypt가 해당 도메인으로
> 실제 접속해서 챌린지 파일을 확인하기 때문이다.

### 2-2. compose.yml에 서비스 추가

`/opt/vps-infra/compose.yml`의 `services:` 아래에 추가한다.

```yaml
  myapp:
    build: ./myapp          # 또는 image: myapp:latest
    container_name: vps-myapp
    restart: unless-stopped
    networks:
      - proxy              # ← 필수. 이게 있어야 nginx가 도달한다
    # ports: 절대 쓰지 말 것. 호스트 포트를 열 이유가 없다.
```

DB가 필요하면 `data` 네트워크도 함께 붙인다:

```yaml
    networks:
      - proxy
      - data
```

그러면 컨테이너 안에서 `postgres:5432`, `redis:6379`로 접근할 수 있다.

환경 변수가 필요하면 `.env`에 추가하고 `.env.example`에도 **더미 값으로** 기록한다.
(`.env` 자체는 Git에 올리지 않는다.)

### 2-3. 인증서에 도메인 추가 ← conf 작성보다 먼저

**① `00-http-challenge.conf`의 `server_name`에 새 도메인을 먼저 추가한다.**

```nginx
server {
    listen 80;
    server_name kkh-hub.tech health.kkh-hub.tech portal.kkh-hub.tech
                jenkins.kkh-hub.tech notes.kkh-hub.tech
                myapp.kkh-hub.tech;          # ← 추가
    ...
}
```

```bash
docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload
```

**② 기존 인증서에 도메인을 덧붙인다.** `-d`에 **기존 도메인을 전부 다시 나열**해야
한다. 빠뜨린 도메인은 인증서에서 제거된다.

```bash
cd /opt/vps-infra
docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot -w /var/www/certbot \
  --cert-name kkh-hub.tech \
  --expand \
  -d kkh-hub.tech \
  -d health.kkh-hub.tech \
  -d portal.kkh-hub.tech \
  -d jenkins.kkh-hub.tech \
  -d notes.kkh-hub.tech \
  -d myapp.kkh-hub.tech \
  --agree-tos --no-eff-email -m 11kkh19@naver.com
```

> ⚠️ `--entrypoint certbot`을 **반드시** 붙인다. compose의 기본 entrypoint는
> 12시간 renew 루프라서, 빼면 인자가 통째로 무시되고
> "No renewals were attempted"만 나온다. (실제로 두 번 겪은 함정)

> 처음 시도라면 `--dry-run`을 붙여 검증하는 것을 권장한다. Let's Encrypt는
> rate limit이 있다 (동일 도메인 세트 주당 5회).

**③ 확인:**

```bash
docker compose run --rm --entrypoint certbot certbot certificates
# Domains: 에 myapp.kkh-hub.tech 가 보여야 함
```

### 2-4. nginx conf 파일 작성

`/opt/vps-infra/nginx/conf.d/myapp.conf`:

```nginx
server {
    listen 443 ssl;
    server_name myapp.kkh-hub.tech;

    ssl_certificate     /etc/letsencrypt/live/kkh-hub.tech/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kkh-hub.tech/privkey.pem;

    location / {
        proxy_pass http://myapp:8080;    # 컨테이너 이름 : 컨테이너 내부 포트
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**변형 패턴**

WebSocket을 쓴다면 (`jenkins.conf` 참고):

```nginx
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 90s;
```

정적 사이트라면 (`notes.conf` 참고) — `proxy_pass` 대신:

```nginx
    root /var/www/myapp;
    location / {
        try_files $uri $uri.html $uri/index.html =404;
    }
```

그리고 `compose.yml`의 nginx에 마운트를 추가한다:

```yaml
      - /opt/myapp-site:/var/www/myapp:ro
```

Basic Auth를 걸려면:

```bash
# 호스트에서 (htpasswd가 없으면 apt-get install apache2-utils)
htpasswd -c /opt/nginx-auth/myapp.htpasswd myuser
```

```yaml
      - /opt/nginx-auth/myapp.htpasswd:/etc/nginx/myapp.htpasswd:ro
```

```nginx
    auth_basic           "MyApp";
    auth_basic_user_file /etc/nginx/myapp.htpasswd;
```

### 2-5. 배포

```bash
cd /opt/vps-infra
git pull
docker compose config >/dev/null       # 문법 검증
docker compose up -d --build myapp     # 새 서비스만
docker compose up -d nginx             # 볼륨 추가했다면 재생성 필요
# 볼륨 변경이 없다면 reload로 충분:
docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload
```

확인:

```bash
curl -I https://myapp.kkh-hub.tech
docker compose logs -f myapp
```

### 2-6. Jenkins Job 등록 (CI/CD가 필요하다면)

**① 소스 저장소에 `Jenkinsfile`을 둔다.** (vps-infra가 아니라 그 서비스 저장소)
`quartz-site-private/Jenkinsfile`이 참고할 만한 완성형 예시다.

기본 골격:

```groovy
pipeline {
    agent any
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    environment {
        BUILD_DIR = '/opt/myapp-build'
    }
    stages {
        stage('Checkout') {
            steps {
                // checkout scm을 써야 Jenkins가 빌드 리비전(sha1)을 기록한다.
                // 수동 git 명령을 쓰면 기록이 안 남아 웹훅 폴링이
                // 항상 "No changes"로 끝나고 자동 트리거가 동작하지 않는다.
                dir(env.BUILD_DIR) { checkout scm }
            }
        }
        stage('Build') {
            steps {
                // Jenkins 이미지에는 언어 런타임이 없다.
                // 필요한 툴체인은 docker run으로 가져온다.
                // -v 경로는 호스트 기준임에 주의.
                sh '''
                    set -eu
                    docker run --rm -v "${BUILD_DIR}:/app" -w /app node:22-slim \
                        sh -ceu '
                            trap "chown -R 1000:1000 /app" EXIT
                            npm ci && npm run build
                        '
                '''
            }
        }
        stage('Deploy') {
            steps {
                sh 'cd /opt/vps-infra && docker compose up -d --build myapp'
            }
        }
        stage('Verify') {
            steps {
                // nginx를 거쳐 확인. --connect-to로 컨테이너에 직접 붙는다.
                sh '''
                    set -eu
                    status="$(curl -sS -o /dev/null -w '%{http_code}' \
                        --connect-to myapp.kkh-hub.tech:443:vps-nginx:443 \
                        https://myapp.kkh-hub.tech/ || true)"
                    echo "[verify] HTTP $status"
                    test "$status" = "200"
                '''
            }
        }
    }
}
```

**② Jenkins 웹 UI에서 Job 생성**
`New Item` → `Pipeline` → 이름 입력

- `GitHub project`: 저장소 URL
- **Build Triggers**: `GitHub hook trigger for GITScm polling` 체크
- **Pipeline**: `Pipeline script from SCM`
  - SCM: `Git`
  - Repository URL: 저장소 URL
  - Credentials: `github-pat`
  - Branch: `*/main`
  - Script Path: `Jenkinsfile`
  - `Lightweight checkout`은 **체크 해제** (트리거 판정에 필요)

**③ GitHub 저장소에 웹훅 등록**
Settings → Webhooks → Add webhook

- Payload URL: `https://jenkins.kkh-hub.tech/github-webhook/`
- Content type: `application/json`
- Events: `Just the push event`

**④ 빌드 산출물 경로가 필요하면 `jenkins/compose.yml`에 마운트 추가**

```yaml
      - /opt/myapp-build:/opt/myapp-build
```

호스트와 **같은 경로**로 마운트해야 파이프라인의 `docker run -v`와 값이 맞는다.
추가 후 Jenkins 재시작:

```bash
cd /opt/vps-infra/jenkins && docker compose up -d
```

---

## 3. 자주 겪는 문제

| 증상 | 원인 | 해결 |
|------|------|------|
| `port is already allocated` | 기존 컨테이너가 80/443 점유 | `docker ps`로 찾아 `docker stop` |
| certbot "No renewals were attempted" | `--entrypoint certbot` 누락 | 2-3의 명령 형태 그대로 사용 |
| 인증서 발급 실패 | `00-http-challenge.conf`에 도메인 미등록, 또는 DNS 미전파 | 2-1, 2-3 ① 확인 |
| `502 Bad Gateway` | 서비스가 `proxy` 네트워크에 없음 / 컨테이너 이름·포트 오타 | `docker compose exec nginx wget -qO- http://myapp:8080` |
| `404` (정적 사이트) | 산출물이 실제로 배포 경로에 없음 | `ls /opt/myapp-site` 확인 |
| Jenkins 자동 트리거 안 됨 | 웹훅 저장소 ≠ Job SCM URL, 또는 `checkout scm` 미사용 | 2-6 ①② 확인 |
| Jenkins `Permission denied` | 컨테이너가 root로 만든 파일이 남음 | `docker run --rm -v <경로>:/t alpine chown -R 1000:1000 /t` |
| 빌드가 유난히 느림 | VPS 2코어인데 툴 기본값이 4스레드 | 동시성 옵션을 2로 명시 |

**진단 순서** — 바깥에서 안으로:

```bash
dig +short myapp.kkh-hub.tech                        # 1. DNS
curl -I http://myapp.kkh-hub.tech                    # 2. :80 리다이렉트
curl -I https://myapp.kkh-hub.tech                   # 3. TLS + 라우팅
docker compose exec nginx nginx -t                   # 4. nginx 설정 문법
docker compose exec nginx wget -qO- http://myapp:8080  # 5. nginx→서비스 도달
docker compose logs myapp                            # 6. 서비스 자체
```

---

## 4. 체크리스트 (요약)

새 서비스 `myapp.kkh-hub.tech` 추가 시:

- [ ] DNS A 레코드 `myapp` → `187.77.114.68`, `dig`로 전파 확인
- [ ] `compose.yml`에 서비스 추가 (`networks: [proxy]`, `ports:` 없이)
- [ ] `00-http-challenge.conf`의 `server_name`에 도메인 추가 → nginx reload
- [ ] certbot `--expand`로 인증서 갱신 (기존 도메인 전부 나열, `--entrypoint certbot`)
- [ ] `nginx/conf.d/myapp.conf` 작성
- [ ] `docker compose up -d --build myapp` + nginx reload
- [ ] `curl -I https://myapp.kkh-hub.tech`로 확인
- [ ] (CI/CD 필요 시) 소스 저장소에 `Jenkinsfile`, Jenkins Job, GitHub 웹훅
- [ ] 이 문서의 1-2 도메인 표에 새 서비스 추가

---

## 관련 문서

- `README.md` — 저장소 개요
- `jenkins/README.md` — Jenkins 초기 설정
- `.okf/services/nginx.md` — nginx 리버스 프록시 상세
- `.okf/decisions/subdomain-routing.md` — 서브도메인 라우팅 결정 배경
- `.okf/runbooks/failure-diagnosis.md` — 장애 진단 런북
- `.okf/environments/hostinger-vps.md` — VPS 환경 메타데이터
