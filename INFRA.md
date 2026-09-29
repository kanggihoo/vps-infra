# 인프라 현황 및 신규 서비스 추가 가이드

이 문서는 repository의 현재 코드가 정의하는 Hostinger VPS 인프라를 설명한다.
기준 파일은 `compose.yml`, `jenkins/compose.yml`, `nginx/templates/*.template`,
`scripts/`, `jenkins/`, `secrets/`다.

## 1. 현재 구조

| 항목 | 값 |
|------|-----|
| Provider | Hostinger VPS |
| Public IP | `187.77.114.68` |
| Domain | `kkh-hub.tech` |
| SSH user | `kkh` |
| 배포 checkout | `~/app/vps-infra` |
| 공개 포트 | `80`, `443` |
| Reverse proxy | nginx |
| 자동 배포 | VPS 내부 Jenkins webhook |
| 빌드 위치 | VPS 내부 Docker daemon |

### 공개 route

| 도메인 | 대상 | 내부 주소 | 인증 |
|--------|------|-----------|------|
| `health.kkh-hub.tech` | whoami | `http://whoami:80` | 없음 |
| `portal.kkh-hub.tech` | portal | `http://portal:8080` | 없음 |
| `jenkins.kkh-hub.tech` | Jenkins | `http://jenkins:8080` | Jenkins 로그인 |
| `notes.kkh-hub.tech` | nginx 정적 파일 | `/var/www/notes` | Basic Auth |
| `kkh-hub.tech` | nginx | HTTP에서 HTTPS로 redirect | 없음 |

PostgreSQL과 Redis는 `vps_data`에만 연결되며 host port를 publish하지 않는다.

### 네트워크

```text
Internet
  -> :80/:443
  -> nginx
  -> vps_proxy
       -> whoami
       -> portal
       -> Jenkins
       -> notes volume

vps_data
  -> PostgreSQL
  -> Redis
```

`vps_proxy`에 연결된 컨테이너는 Docker DNS로 서비스 이름을 사용할 수 있다.
PostgreSQL과 Redis는 `vps_data`에만 있으므로 nginx에서 직접 접근할 수 없다.

## 2. Compose 프로젝트

### 공용 인프라 Compose

루트 `compose.yml`이 다음 서비스를 관리한다.

- `nginx`: public HTTP/HTTPS 진입점
- `certbot`: Let's Encrypt 인증서 발급·갱신
- `whoami`: DNS/TLS/nginx/Docker 네트워크 검증용 backend
- `portal`: Go HTTP server와 React 정적 파일
- `postgres`: 공용 PostgreSQL
- `redis`: 공용 Redis
- `tools`: SOPS와 검증 스크립트 실행용 일회성 컨테이너

`tools`는 상주하지 않으며 명령 실행 때만 생성한다.

```bash
docker compose run --rm tools ./scripts/test-sops.sh
```

### Jenkins Compose

`jenkins/compose.yml`은 Jenkins만 별도 관리한다.

- `vps_proxy`를 external network로 참조
- `vps_jenkins_data` named volume에 `/var/jenkins_home` 저장
- `/var/run/docker.sock`을 사용해 host Docker daemon 제어
- `APP_DIR_HOST`를 컨테이너의 `APP_DIR`과 같은 경로로 bind mount
- `mem_limit` 기본값 `2g`, JVM heap 기본값 `1g`

Jenkins를 공용 Compose에 넣지 않는 이유는 인프라 배포가 Jenkins 자신을 재생성하지
않도록 하기 위해서다.

## 3. nginx 설정 구조

호스트에서 수정하는 nginx source는 다음이다.

```text
nginx/
├── nginx.conf
├── templates/
│   ├── 00-http-challenge.conf.template
│   ├── health.conf.template
│   ├── jenkins.conf.template
│   ├── notes.conf.template
│   └── portal.conf.template
└── tls/
    ├── live.conf
    ├── live-challenge.conf
    ├── none.conf
    └── none-challenge.conf
```

nginx 공식 이미지가 컨테이너 시작 시 `nginx/templates/*.template`를 환경변수로
치환해 `/etc/nginx/conf.d/*.conf`를 생성한다. repository에 `nginx/conf.d/`를
만들거나 생성된 `.conf`를 직접 수정하지 않는다.

환경변수:

| 변수 | 로컬 | VPS |
|------|------|-----|
| `BASE_DOMAIN` | `localhost` | `kkh-hub.tech` |
| `NGINX_LISTEN` | `80` | `443 ssl` |
| `TLS_MODE` | `none` | `live` |
| `CHALLENGE_DOMAINS` | 테스트 도메인 | 인증서 대상 전체 |

새 public route를 추가할 때:

1. `nginx/templates/<service>.conf.template` 추가
2. 필요하면 `CHALLENGE_DOMAINS`에 도메인 추가
3. `docker compose config` 실행
4. CI 또는 로컬에서 nginx template 문법 검증
5. nginx를 recreate해 template 재치환

```bash
docker compose up -d --force-recreate nginx
docker compose exec nginx nginx -t
```

Jenkins route는 별도 Compose 프로젝트의 컨테이너가 늦게 올라올 수 있으므로
`jenkins.conf.template`에서 Docker DNS resolver와 변수 upstream을 사용한다.

## 4. Secret 관리

평문 secret은 Git에 커밋하지 않는다. SOPS 암호화 파일은 Git에 커밋한다.

```text
secrets/env.local.sops.env
secrets/env.prod.sops.env
secrets/notes.htpasswd.sops.txt
secrets/github-pat.sops.txt
```

- SOPS: 암호화·복호화 관리 도구
- age: 복호화 key backend
- age private key: `~/.config/sops/age/keys.txt`에만 보관
- 복호화 결과: `.env`, `secrets/notes.htpasswd` 등 Gitignored 파일

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) \
  docker compose run --rm tools ./scripts/secrets.sh decrypt

docker compose run --rm --no-deps tools ./scripts/test-sops.sh
./scripts/check-sops.sh
```

Jenkins가 사용할 GitHub credential과 SOPS age key는 JCasC 환경변수로 주입한다.
실제 값은 `jenkins/.env`에 두며 이 파일은 Git에 커밋하지 않는다.

## 5. 배포 흐름

```text
GitHub push
  -> GitHub webhook
  -> Jenkins
  -> repository checkout
  -> docker compose config
  -> scripts/deploy.sh
  -> scripts/healthcheck.sh
```

Jenkins는 `Jenkinsfile`의 배포 대상을 판정하고 VPS Docker daemon에서 이미지를 직접
빌드한다. GHCR는 사용하지 않는다.

GitHub Actions는 현재 배포하지 않는다. `.github/workflows/validate.yml`에서 다음만
검증한다.

- Compose 문법
- nginx template 렌더링 및 `nginx -t`
- 배포 대상 판정 script
- SOPS roundtrip
- 암호화 파일 무결성

## 6. Jenkins 초기 설정

Jenkins 실행 source는 `~/app/vps-infra/jenkins/`다.

```text
jenkins/
├── compose.yml
├── Dockerfile
├── .env.example
├── casc/
│   ├── jenkins.yaml
│   └── jobs.groovy
└── plugins.txt
```

`casc/`는 이미지에 넣지 않고 컨테이너에 마운트한다. push하면 vps-infra 파이프라인이
`git pull` 후 JCasC를 reload하므로, 설정 변경이나 Job 추가에 재빌드가 필요 없다.
`plugins.txt`, `Dockerfile`, `.env`를 바꿀 때만 VPS에서 `up -d --build`를 실행한다.

실행 환경변수 파일은 `~/app/vps-infra/jenkins/.env`다. Git에 커밋되지 않는다.

```bash
cd ~/app/vps-infra/jenkins
cp .env.example .env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" .env
docker compose --env-file .env up -d --build
```

`DOCKER_GID`는 host의 `docker` 그룹 숫자 ID다. Compose의 `group_add`가 이 값을
컨테이너에 추가해 Jenkins가 `/var/run/docker.sock`을 사용할 수 있게 한다.

repository에는 JCasC와 Job DSL 설정이 있지만, VPS에 적용하기 전에는 기존 Jenkins
volume의 수동 설정이 계속 사용될 수 있다. 실제 적용 여부는
`okf/runbooks/local-first-handover.md`의 단계 6-b를 확인한다.

## 7. 신규 서비스 추가

현재 결정은 **프로젝트별 독립 Compose**다. 새 프로젝트는 자기 repository에서
`compose.yml`, `Dockerfile`, `Jenkinsfile`을 소유한다. 공용 인프라에 직접 속하는
서비스만 이 repository의 루트 `compose.yml`에 추가한다.

### public HTTP 서비스

1. DNS A record를 VPS public IP에 연결한다.
2. 서비스 Compose를 `vps_proxy`에 연결한다.
3. host `ports`는 publish하지 않는다.
4. nginx template을 추가한다.
5. `CHALLENGE_DOMAINS`와 인증서 대상에 도메인을 추가한다.
6. `docker compose config`, nginx 문법, healthcheck을 실행한다.

예시:

```yaml
services:
  myapp:
    build: .
    restart: unless-stopped
    networks:
      - proxy

networks:
  proxy:
    external: true
    name: vps_proxy
```

nginx template:

```nginx
server {
    listen ${NGINX_LISTEN};
    server_name myapp.${BASE_DOMAIN};
    include /etc/nginx/tls/${TLS_MODE}.conf;

    location / {
        proxy_pass http://myapp:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 데이터베이스 연결

서비스가 공용 PostgreSQL 또는 Redis를 사용하면 `vps_data`에도 연결한다.
접속 hostname은 Compose service name이다.

```yaml
networks:
  - proxy
  - data

networks:
  proxy:
    external: true
    name: vps_proxy
  data:
    external: true
    name: vps_data
```

secret은 평문 `.env`에만 두고, repository에 저장해야 하면 SOPS로 암호화한다.

## 8. 검증 명령

```bash
docker compose config
docker compose -f jenkins/compose.yml config
./scripts/test-select-target.sh
./scripts/test-routing.sh
./scripts/healthcheck.sh
./scripts/check-sops.sh
```

Jenkins 없이 공용 stack만 검증하면 Jenkins route는 `502`가 될 수 있다. 이는 nginx
template이 Jenkins 부재 상태에서도 기동하도록 설계된 정상 결과다.

## 관련 문서

- `okf/architecture/system-overview.md`
- `okf/services/nginx.md`
- `okf/services/jenkins-deploy.md`
- `okf/runbooks/local-first-handover.md`
- `okf/runbooks/failure-diagnosis.md`
- `okf/adr/0007-per-project-compose.md`
- `okf/adr/0008-nginx-env-templates.md`
- `okf/adr/0010-sops-secrets.md`
