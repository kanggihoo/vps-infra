#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

echo "[healthcheck] docker compose config"
docker compose config >/dev/null

echo "[healthcheck] containers"
docker compose ps

echo "[healthcheck] postgres"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[healthcheck] redis"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[healthcheck] public health route"
curl -fsS https://health.kkh-hub.tech >/dev/null

echo "[healthcheck] traefik dashboard auth"
dashboard_status="$(curl -sS -o /dev/null -w "%{http_code}" https://traefik.kkh-hub.tech)"
test "$dashboard_status" = "401"

echo "[healthcheck] ok"
