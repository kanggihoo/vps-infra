#!/usr/bin/env bash
# deploy.sh의 .env 가드를 확인한다. 스택을 띄우지 않으므로 CI에서 돈다.
#
# deploy.sh를 임시 디렉터리에 복사해 .env만 바꿔 실행한다. 가드는 docker를 부르기 전에 끝나므로
# PATH 앞에 exit 97만 하는 가짜 docker를 둔다.
#   exit 2  + 기대 메시지 = 가드가 막았다
#   exit 97              = 가드를 모두 통과하고 첫 docker 호출(compose config)까지 왔다
set -euo pipefail

cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts" "$work/bin"
cp scripts/deploy.sh "$work/scripts/"
: > "$work/compose.yml"
printf '#!/bin/sh\nexit 97\n' > "$work/bin/docker"
chmod +x "$work/bin/docker"

# 로컬 테스트 계정 test/test. 작은따옴표 안이므로 셸이 $를 치환하지 않는다.
test_users="'test:\$2y\$10\$abcdefghijklmnopqrstuuWmQ6nHqL9b8bH0x2u2JYdJk6Qm7nV2a'"
real_users="'owner:\$2y\$10\$abcdefghijklmnopqrstuuWmQ6nHqL9b8bH0x2u2JYdJk6Qm7nV2a'"

fail=0

# expect <설명> <기대 exit> <기대 메시지(없으면 -)> <.env 줄...>
expect() {
  local desc="$1" want="$2" msg="$3"
  shift 3
  printf '%s\n' "$@" > "$work/.env"
  local out code=0
  out="$(PATH="$work/bin:$PATH" "$work/scripts/deploy.sh" all 2>&1)" || code=$?
  if [ "$code" = "$want" ] && { [ "$msg" = - ] || printf '%s' "$out" | grep -qF "$msg"; }; then
    echo "ok   - $desc (exit $code)"
  else
    echo "FAIL - $desc: want exit $want '$msg', got exit $code" >&2
    printf '%s\n' "$out" | tail -3 >&2
    fail=1
  fi
}

live=(TLS_MODE=live "TINYAUTH_OAUTH_WHITELIST=owner@example.com")

expect "live 정상 설정은 가드를 통과한다" 97 - \
  "${live[@]}" "TINYAUTH_AUTH_USERS=$real_users"
expect "live에서 빈 TINYAUTH_AUTH_USERS를 막는다" 2 "TINYAUTH_AUTH_USERS가 필요하다" \
  "${live[@]}" "TINYAUTH_AUTH_USERS="
expect "live에서 test 계정을 막는다" 2 "로컬 테스트 계정(test)" \
  "${live[@]}" "TINYAUTH_AUTH_USERS=$test_users"
expect "live에서 여러 계정 중 test 계정도 막는다" 2 "로컬 테스트 계정(test)" \
  "${live[@]}" "TINYAUTH_AUTH_USERS='owner:x,test:y'"
expect "live에서 빈 화이트리스트를 막는다" 2 "TINYAUTH_OAUTH_WHITELIST가 필요하다" \
  TLS_MODE=live "TINYAUTH_AUTH_USERS=$real_users" "TINYAUTH_OAUTH_WHITELIST="
expect "작은따옴표 없는 \$ 값을 막는다" 2 "작은따옴표 없는" \
  "${live[@]}" 'TINYAUTH_AUTH_USERS=owner:$2y$10$abc'
expect "큰따옴표 안의 \$ 값도 막는다" 2 "작은따옴표 없는" \
  "${live[@]}" 'TINYAUTH_AUTH_USERS="owner:$2y$10$abc"'
expect "로컬은 test 계정과 빈 화이트리스트로 통과한다" 97 - \
  TLS_MODE=none "TINYAUTH_AUTH_USERS=$test_users" "TINYAUTH_OAUTH_WHITELIST="
expect "로컬도 Google client가 있으면 빈 화이트리스트를 막는다" 2 "Google OAuth를 쓰려면" \
  TLS_MODE=none "TINYAUTH_AUTH_USERS=$test_users" "TINYAUTH_OAUTH_PROVIDERS_GOOGLE_CLIENTID=abc" "TINYAUTH_OAUTH_WHITELIST="

if [ "$fail" -ne 0 ]; then
  echo "deploy guards: FAILED" >&2
  exit 1
fi
echo "deploy guards: all passed"
