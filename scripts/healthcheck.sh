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

echo "[healthcheck] public health route (${health_scheme}://${health_host})"
for attempt in $(seq 1 12); do
  if public_curl "$health_host" -fsS >/dev/null; then
    break
  fi
  if [ "$attempt" = 12 ]; then
    echo "[healthcheck] public health route failed after ${attempt} attempts" >&2
    exit 1
  fi
  sleep 5
done

echo "[healthcheck] ok"
