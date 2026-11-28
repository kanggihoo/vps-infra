# 인프라 현황 및 신규 서비스 추가 가이드

이 문서는 repository의 현재 코드가 정의하는 Hostinger VPS 인프라를 설명한다.
기준 파일은 `compose.yml`, `observability/compose.yml`, `nginx/templates/*.template`,
`scripts/`, `.github/workflows/validate.yml`, `secrets/`다.

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
| 자동 배포 | GitHub Actions → SSH forced command `scripts/ci-deploy.sh` |
| 빌드 위치 | VPS 내부 Docker daemon |

### 공개 route

| 도메인 | 대상 | 내부 주소 | 인증 |
|--------|------|-----------|------|
| `health.kkh-hub.tech` | whoami | `http://whoami:80` | 없음 |
| `portal.kkh-hub.tech` | portal | `http://portal:8080` | 없음 |
| `auth.kkh-hub.tech` | Tinyauth 로그인 포털 | `http://tinyauth:3000` | 없음 |
| `notes.kkh-hub.tech` | nginx 정적 파일 | `/var/www/notes` | Tinyauth SSO |
| `erd.kkh-hub.tech` | nginx 정적 파일 | `/var/www/erd` | Tinyauth SSO |
| `info.kkh-hub.tech` | vps-info | `http://vps-info-app:8000` | Tinyauth SSO |
| `grafana.kkh-hub.tech` | Grafana | `http://grafana:3000` | Tinyauth SSO (Auth Proxy) |
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

## 3. nginx 설정 구조

호스트에서 수정하는 nginx source는 다음이다.

```text
nginx/
├── nginx.conf
├── templates/
│   ├── 00-http-challenge.conf.template
│   ├── health.conf.template
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

## 4. Secret 관리

평문 secret은 Git에 커밋하지 않는다. SOPS 암호화 파일은 Git에 커밋한다.

```text
secrets/env.local.sops.env
secrets/env.prod.sops.env
```

Tinyauth 계정(`TINYAUTH_AUTH_USERS`), Google OAuth client와 허용 이메일(`TINYAUTH_OAUTH_*`)도 이 `.env`에 있다.
bcrypt 해시처럼 `$`가 든 값은 작은따옴표로 감싼다([ADR 0022](docs/adr/0022-tinyauth-sso.md)).

- SOPS: 암호화·복호화 관리 도구
- age: 복호화 key backend
- age private key: `~/.config/sops/age/keys.txt`에만 보관
- 복호화 결과: `.env` (Gitignored)

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) \
  docker compose run --rm tools ./scripts/secrets.sh decrypt

docker compose run --rm --no-deps tools ./scripts/test-sops.sh
./scripts/check-sops.sh
```

운영 배포는 `scripts/ci-deploy.sh`가 `ENV_NAME=prod`로 `tools` 컨테이너에서 `secrets.sh decrypt`를 실행한다.
VPS의 key는 `~/.config/sops/age/keys.txt` 하나다.

## 5. 배포 흐름

```text
main push
  -> GitHub Actions validate job
  -> deploy job: ssh kkh@187.77.114.68 "<sha> <target>" (secret VPS_DEPLOY_KEY)
  -> authorized_keys forced command: ~/app/vps-infra/scripts/ci-deploy.sh
       -> flock /tmp/vps-deploy.lock
       -> git checkout <sha> (main 이력만)
       -> 대상 판정 (auto면 .deploy-state + scripts/select-target.sh, 아니면 all|portal|observability)
       -> docker compose run --rm --no-deps -T tools ./scripts/secrets.sh decrypt (ENV_NAME=prod)
       -> scripts/deploy.sh <target>
       -> HEALTHCHECK_CONNECT_HOST=127.0.0.1 scripts/healthcheck.sh
       -> .deploy-state/last-successful-sha 기록
  -> notify job: Mattermost (secret MATTERMOST_WEBHOOK_URL)
```

portal과 tools 이미지는 VPS Docker daemon에서 직접 빌드한다. vps-infra는 GHCR를 사용하지 않는다.

validate job은 PR과 main에서 다음을 검증한다.

- Compose 문법
- nginx template 렌더링 및 `nginx -t`
- 배포 대상 판정 script
- SOPS roundtrip
- 암호화 파일 무결성

수동 재배포·롤백은 Actions `workflow_dispatch`(`target`: auto|all|portal|observability)나 VPS에서
`~/app/vps-infra/scripts/ci-deploy.sh <sha> all`로 한다.

`ci-deploy.sh`를 바꾸면 그 변경은 **다음 배포부터** 적용된다. VPS에 이미 있는 버전이 먼저 실행돼
새 커밋을 checkout하기 때문이다. 상세는 `okf/services/deploy.md`와 `docs/adr/0020-infra-cd-on-github-actions.md`에 있다.

## 6. 신규 서비스 추가

현재 결정은 **프로젝트별 독립 Compose**다. 새 프로젝트는 자기 repository에서
`compose.yml`, `Dockerfile`, 배포 workflow를 소유한다. 공용 인프라에 직접 속하는
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

## 7. 검증 명령

```bash
docker compose config
./scripts/test-select-target.sh
./scripts/test-routing.sh
./scripts/healthcheck.sh
./scripts/check-sops.sh
```

## 관련 문서

- `okf/architecture/system-overview.md`
- `okf/services/nginx.md`
- `okf/services/deploy.md`
- `docs/adr/0021-remove-jenkins.md`
- `okf/runbooks/local-first-handover.md`
- `okf/runbooks/failure-diagnosis.md`
- `docs/adr/0007-per-project-compose.md`
- `docs/adr/0008-nginx-env-templates.md`
- `docs/adr/0010-sops-secrets.md`
