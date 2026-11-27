#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

# 도메인과 스킴을 환경변수로 받는다. 하드코딩하면 로컬에서 항상 실패한다.
#   로컬  HEALTHCHECK_HOST=health.vps.localhost  HEALTHCHECK_SCHEME=http
#   VPS   HEALTHCHECK_HOST=health.kkh-hub.tech HEALTHCHECK_SCHEME=https
base_domain="${BASE_DOMAIN:-vps.localhost}"
health_host="${HEALTHCHECK_HOST:-health.${base_domain}}"
health_scheme="${HEALTHCHECK_SCHEME:-http}"
portal_host="${PORTAL_HEALTHCHECK_HOST:-portal.${base_domain}}"

public_curl() {
  local host="$1" path="$2"
  shift 2
  local port=443
  [ "$health_scheme" = "http" ] && port=80

  # 배포(ci-deploy.sh)는 공개 DNS를 거치지 않고 호스트의 nginx(127.0.0.1)로 직접 붙는다.
  if [ -n "${HEALTHCHECK_CONNECT_HOST:-}" ]; then
    curl --connect-timeout 5 --max-time 15 \
      --connect-to "${host}:${port}:${HEALTHCHECK_CONNECT_HOST}:${port}" \
      "${health_scheme}://${host}${path}" "$@"
  else
    curl --connect-timeout 5 --max-time 15 "${health_scheme}://${host}${path}" "$@"
  fi
}

echo "[healthcheck] docker compose config"
docker compose config >/dev/null

echo "[healthcheck] containers"
docker compose ps

echo "[healthcheck] postgres"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[healthcheck] redis"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

check_public_route() {
  local name="$1" host="$2" expected="${3:-}"
  local path=/ response
  if [[ -n "$expected" ]]; then
    path=/api/version
  fi

  echo "[healthcheck] ${name} route (${health_scheme}://${host})"
  for attempt in $(seq 1 12); do
    if response="$(public_curl "$host" "$path" -fsS)" &&
       [[ -z "$expected" || "$response" == "$expected" ]]; then
      return 0
    fi
    if [ "$attempt" = 12 ]; then
      echo "[healthcheck] ${name} route failed after ${attempt} attempts" >&2
      return 1
    fi
    sleep 5
  done
}

# whoami는 DNS, TLS, nginx 경로를 확인하고 portal은 실제 배포 대상을 확인한다.
check_public_route "health" "$health_host"
check_public_route "portal" "$portal_host" "${EXPECTED_PORTAL_SHA:-}"
# Tinyauth 로그인 포털. 공개 서브도메인이라 200이어야 한다.
check_public_route "auth" "auth.${base_domain}"

# 보호 서브도메인은 미인증 요청을 auth 로그인으로 302 보내야 한다.
# 200이면 인증이 빠진 것이고, 5xx면 Tinyauth나 nginx 연결이 깨진 것이다.
login_prefix="${health_scheme}://auth.${base_domain}/login?"
for name in erd notes info grafana; do
  host="${name}.${base_domain}"
  echo "[healthcheck] ${name} redirects to login (${health_scheme}://${host})"
  got="$(public_curl "$host" / -sS -o /dev/null -w '%{http_code} %{redirect_url}' || true)"
  case "$got" in
    "302 ${login_prefix}"*) ;;
    *) echo "[healthcheck] ${name} want 302 to ${login_prefix}..., got: ${got}" >&2; exit 1 ;;
  esac
done

# Grafana 생존은 인증 뒤 공개 이름 대신 vps_proxy 안에서 직접 본다(ADR 0016, 별도 compose 프로젝트).
echo "[healthcheck] grafana internal health (http://grafana:3000/api/health)"
for attempt in $(seq 1 12); do
  if docker compose exec -T nginx wget -qO- http://grafana:3000/api/health >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" = 12 ]; then
    echo "[healthcheck] grafana internal health failed after ${attempt} attempts" >&2
    exit 1
  fi
  sleep 5
done

echo "[healthcheck] ok"
