#!/usr/bin/env bash
# Hostinger VPS의 systemd timer가 12시간마다 호출한다.
# certbot 컨테이너에는 Docker socket을 주지 않고, reload는 호스트가 수행한다.
set -euo pipefail

cd "$(dirname "$0")/.."

test -f .env
set -a
. ./.env
set +a

if [ "${TLS_MODE:-none}" != "live" ]; then
  echo "[certbot] TLS_MODE=live 환경에서만 인증서를 갱신할 수 있다" >&2
  exit 2
fi

echo "[certbot] renewing certificates"
docker compose run --rm --no-deps --entrypoint certbot certbot \
  renew --webroot -w /var/www/certbot

# renew가 성공한 경우에만 실행한다. 실제 갱신이 없더라도 reload는 무해하고,
# nginx가 새 파일을 읽는지 매 주기 확인할 수 있다.
echo "[certbot] validating nginx configuration"
docker compose exec -T nginx nginx -t

echo "[certbot] reloading nginx certificates"
docker compose exec -T nginx nginx -s reload
