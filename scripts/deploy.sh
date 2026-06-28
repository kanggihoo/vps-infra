#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[deploy] checking required files"
test -f .env
test -f compose.yml
test -f traefik/acme.json

echo "[deploy] validating compose"
docker compose config >/dev/null

echo "[deploy] pulling images"
docker compose pull

echo "[deploy] applying stack"
docker compose up -d

echo "[deploy] compose status"
docker compose ps

echo "[deploy] local postgres check"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[deploy] local redis check"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[deploy] complete"
