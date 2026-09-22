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

# live TLS에서 test/test fixture로 시작하면 notes 인증이 공개된다.
# 로컬 clean clone은 fixture를 계속 쓸 수 있고, 운영 진입점만 명확히 막는다.
if [ "${TLS_MODE:-none}" = "live" ] && \
   [ "${NOTES_HTPASSWD:-}" = "./nginx/test-fixtures/notes.htpasswd" ]; then
  echo "[deploy] TLS_MODE=live에서는 NOTES_HTPASSWD에 실제 secret 파일이 필요하다" >&2
  exit 2
fi

echo "[deploy] validating compose"
docker compose config >/dev/null

validate_nginx_template() {
  echo "[deploy] validating rendered nginx template"
  # nginx 공식 entrypoint가 envsubst를 실행한 뒤 nginx -t를 수행한다.
  # 포트를 publish하지 않는 일회성 컨테이너라 현재 nginx에 영향이 없다.
  docker compose run --rm --no-deps nginx nginx -t
}

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

validate_nginx_template

echo "[deploy] applying stack"
docker compose up -d --build --wait --wait-timeout 120

# bind mount의 template만 바뀌면 일반 up은 nginx를 재생성하지 않는다.
# 후보 설정 검증을 통과한 뒤 nginx만 강제로 재생성해 envsubst 결과를 갱신한다.
echo "[deploy] recreating nginx for rendered configuration"
docker compose up -d --no-deps --force-recreate --wait --wait-timeout 120 nginx

echo "[deploy] compose status"
docker compose ps

echo "[deploy] local postgres check"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[deploy] local redis check"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[deploy] complete"
