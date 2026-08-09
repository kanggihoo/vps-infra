#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

public_curl() {
  local host="$1"
  shift

  if [ -n "${HEALTHCHECK_CONNECT_HOST:-}" ]; then
    curl --connect-timeout 5 --max-time 15 \
      --connect-to "${host}:443:${HEALTHCHECK_CONNECT_HOST}:443" \
      "https://${host}" "$@"
  else
    curl --connect-timeout 5 --max-time 15 "https://${host}" "$@"
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

echo "[healthcheck] public health route"
for attempt in $(seq 1 12); do
  if public_curl health.kkh-hub.tech -fsS >/dev/null; then
    break
  fi
  if [ "$attempt" = 12 ]; then
    echo "[healthcheck] public health route failed after ${attempt} attempts" >&2
    exit 1
  fi
  sleep 5
done

echo "[healthcheck] ok"
