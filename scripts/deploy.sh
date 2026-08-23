#!/usr/bin/env bash
set -euo pipefail

target="${1:-all}"

cd "$(dirname "$0")/.."

case "$target" in
  all|portal) ;;
  *)
    echo "[deploy] unknown target: $target" >&2
    echo "[deploy] usage: $0 [all|portal]" >&2
    exit 2
    ;;
esac

echo "[deploy] checking required files"
test -f .env
test -f compose.yml

# .env를 셸로 읽는다. 공백이 든 값에 따옴표가 없으면 여기서
# "ssl: command not found"처럼 엉뚱한 오류가 나므로 미리 잡아준다.
if grep -qE '^[A-Z_]+=[^"'"'"']*[[:space:]]' .env; then
  echo "[deploy] .env에 따옴표 없는 공백 값이 있다. 예: NGINX_LISTEN=\"443 ssl\"" >&2
  grep -nE '^[A-Z_]+=[^"'"'"']*[[:space:]]' .env | sed 's/=.*/=<...>/' >&2
  exit 2
fi

set -a
. ./.env
set +a

echo "[deploy] validating compose"
docker compose config >/dev/null

if [ "$target" = "portal" ]; then
  echo "[deploy] applying portal only"
  # Portal-only deploy avoids recreating infra services when only React/Go code changed.
  docker compose up -d --build --no-deps portal

  echo "[deploy] portal status"
  docker compose ps portal

  echo "[deploy] complete"
  exit 0
fi

echo "[deploy] pulling images"
docker compose pull --ignore-buildable

echo "[deploy] applying stack"
docker compose up -d --build --wait --wait-timeout 120

echo "[deploy] compose status"
docker compose ps

echo "[deploy] local postgres check"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[deploy] local redis check"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[deploy] complete"
