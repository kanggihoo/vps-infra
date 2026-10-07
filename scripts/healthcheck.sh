#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

# 도메인과 스킴을 환경변수로 받는다. 하드코딩하면 로컬에서 항상 실패한다.
#   로컬  HEALTHCHECK_HOST=health.localhost  HEALTHCHECK_SCHEME=http
#   VPS   HEALTHCHECK_HOST=health.kkh-hub.tech HEALTHCHECK_SCHEME=https
health_host="${HEALTHCHECK_HOST:-health.localhost}"
health_scheme="${HEALTHCHECK_SCHEME:-http}"
portal_host="${PORTAL_HEALTHCHECK_HOST:-portal.${BASE_DOMAIN:-localhost}}"

public_curl() {
  local host="$1"
  shift
  local port=443
  [ "$health_scheme" = "http" ] && port=80

  # Jenkins 안에서는 공개 DNS를 거치지 않고 nginx 컨테이너로 직접 붙는다.
  if [ -n "${HEALTHCHECK_CONNECT_HOST:-}" ]; then
    curl --connect-timeout 5 --max-time 15 \
      --connect-to "${host}:${port}:${HEALTHCHECK_CONNECT_HOST}:${port}" \
      "${health_scheme}://${host}" "$@"
  else
    curl --connect-timeout 5 --max-time 15 "${health_scheme}://${host}" "$@"
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
  local name="$1" host="$2"

  echo "[healthcheck] ${name} route (${health_scheme}://${host})"
  for attempt in $(seq 1 12); do
    if public_curl "$host" -fsS >/dev/null; then
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
check_public_route "portal" "$portal_host"
# 관측 스택(ADR 0016). 별도 compose 프로젝트라 nginx 라우팅과 함께 확인한다.
# 루트는 /login으로 302를 주며, -f는 3xx를 실패로 보지 않는다.
check_public_route "grafana" "grafana.${BASE_DOMAIN:-localhost}"

echo "[healthcheck] ok"
