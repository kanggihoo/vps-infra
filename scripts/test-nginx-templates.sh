#!/usr/bin/env bash
# nginx 템플릿을 로컬 모드와 VPS 모드로 렌더해 `nginx -t`로 문법을 검사한다.
# CI(`ci.yml`)와 로컬에서 같은 명령으로 실행한다. 레포 루트에서 실행한다.
#
# nginx 템플릿은 envsubst 치환 전에는 유효한 conf가 아니다.
# 이미지 entrypoint와 같은 방식으로 렌더한 뒤 `nginx -t`로 문법을 본다.
#
# `nginx -t`는 upstream 이름을 DNS로 해석하므로, 대상 컨테이너가 없으면
# "host not found in upstream"으로 실패한다. 문법만 보려면 이름이 해석되어야
# 하므로 더미 컨테이너를 같은 네트워크에 띄운다. 로컬 스택과 이름이 겹치지
# 않도록 컨테이너 이름은 따로 두고 upstream 이름은 network alias로 준다.
# (grafana, tinyauth는 변수+resolver를 쓰므로 기동 시 해석되지 않아도 된다)
set -euo pipefail

cd "$(dirname "$0")/.."

# Windows Git Bash는 `/CN=...`이나 `a:/b` 같은 인자를 Windows 경로로 바꿔 openssl과
# docker 마운트를 깨뜨린다. 변환을 끄고, openssl에는 상대 경로만 넘긴다. Linux에서는 영향이 없다.
export MSYS_NO_PATHCONV=1

NETWORK=nginx_template_test
STUBS=(whoami portal)
CERT_DIR=$(mktemp -d .nginx-template-test.XXXXXX)

cleanup() {
  for svc in "${STUBS[@]}"; do
    docker rm -f "$NETWORK-$svc" >/dev/null 2>&1 || true
  done
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$CERT_DIR"
}
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null
for svc in "${STUBS[@]}"; do
  docker run -d --rm --name "$NETWORK-$svc" --network "$NETWORK" --network-alias "$svc" \
    traefik/whoami:v1.10 >/dev/null
done

# VPS 모드는 인증서 파일이 있어야 `nginx -t`를 통과한다.
# 더미 인증서를 만들어두면 인증서 경로 오타까지 이 단계에서 드러난다.
# 로컬 모드는 이 마운트를 무시하므로 두 모드가 같은 호출을 쓴다.
mkdir -p "$CERT_DIR/live/kkh-hub.tech"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=kkh-hub.tech' \
  -keyout "$CERT_DIR/live/kkh-hub.tech/privkey.pem" \
  -out "$CERT_DIR/live/kkh-hub.tech/fullchain.pem" >/dev/null 2>&1

validate() {
  echo "--- BASE_DOMAIN=$1 NGINX_LISTEN=$2 TLS_MODE=$3 ---"
  docker run --rm --network "$NETWORK" \
    -e BASE_DOMAIN="$1" \
    -e NGINX_LISTEN="$2" \
    -e TLS_MODE="$3" \
    -e CHALLENGE_DOMAINS="$4" \
    -v "$PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
    -v "$PWD/nginx/templates:/etc/nginx/templates:ro" \
    -v "$PWD/nginx/tls:/etc/nginx/tls:ro" \
    -v "$PWD/$CERT_DIR:/etc/letsencrypt:ro" \
    nginx:1.31.4-alpine-otel \
    sh -c '/docker-entrypoint.sh nginx -t'
}

# 두 모드를 모두 검증한다. 한쪽만 보면 다른 쪽 오타를 놓친다.
validate vps.localhost 80 none acme-challenge.invalid
validate kkh-hub.tech "443 ssl" live \
  "kkh-hub.tech health.kkh-hub.tech portal.kkh-hub.tech notes.kkh-hub.tech auth.kkh-hub.tech"
