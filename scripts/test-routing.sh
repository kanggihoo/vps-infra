#!/usr/bin/env bash
# seam 2 검증. 기동된 스택에 실제 HTTP 요청을 보내 상태 코드와 본문을 본다.
#
# 렌더된 conf를 검사하지 않는 이유: 200 응답 하나가 템플릿 렌더·라우팅·
# 네트워크 연결을 동시에 증명한다. conf 내용을 diff하면 구현을 바꿀 때마다 깨진다.
#
# 전제: docker compose up -d 가 이미 완료된 상태.
#   BASE_URL 로 대상 변경 가능 (기본 http://127.0.0.1)
set -euo pipefail

base_url="${BASE_URL:-http://127.0.0.1}"
base_domain="${BASE_DOMAIN:-localhost}"

fail=0

# check <설명> <Host 헤더> <경로> <기대 상태코드> [curl 추가인자...]
check() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  local got
  got="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    -H "Host: ${host}" "$@" "${base_url}${path}" || echo 000)"
  if [ "$got" = "$want" ]; then
    echo "ok   - $desc ($host$path -> $got)"
  else
    echo "FAIL - $desc: $host$path want $want, got $got" >&2
    fail=1
  fi
}

# body_contains <설명> <Host> <경로> <기대 문자열> [curl 추가인자...]
body_contains() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  local body
  body="$(curl -s --connect-timeout 5 --max-time 15 \
    -H "Host: ${host}" "$@" "${base_url}${path}" || true)"
  if printf '%s' "$body" | grep -q "$want"; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc: '$want' not found in response body" >&2
    fail=1
  fi
}

echo "--- 로컬 HTTP 기동 확인 (TLS 모드 분기) ---"
# 인증서 없이 80에서 응답하면 TLS_MODE=none 분기가 동작한 것이다.
check "portal이 HTTP 80에서 응답" "portal.${base_domain}" / 200

echo "--- 서브도메인 라우팅 ---"
check "health -> whoami" "health.${base_domain}" / 200
body_contains "whoami 응답 본문 확인" "health.${base_domain}" / "Hostname"
check "portal -> portal:8080" "portal.${base_domain}" / 200

echo "--- Basic Auth ---"
# 자격증명 없이 401이어야 한다. 200이면 인증이 빠진 것.
check "notes 인증 없이 401" "notes.${base_domain}" / 401
# fixture 자격증명(test/test)으로는 통과해야 한다.
# 콘텐츠가 없으면 404, 있으면 200 — 둘 다 인증 통과를 뜻한다.
got="$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 \
  -u test:test -H "Host: notes.${base_domain}" "${base_url}/" || echo 000)"
if [ "$got" = "200" ] || [ "$got" = "404" ]; then
  echo "ok   - notes 올바른 자격증명으로 인증 통과 ($got)"
else
  echo "FAIL - notes 자격증명 통과 실패: got $got" >&2
  fail=1
fi

echo "--- 정적 사이트 try_files ---"
# 확장자 없는 경로가 .html로 해석되는지. probe 파일을 볼륨에 넣어 확인한다.
# nginx는 /var/www/notes를 :ro로 마운트하므로 쓰기는 별도 컨테이너로 한다.
docker run --rm -v vps_quartz_site:/w alpine:3.24 \
  sh -c 'echo "<h1>note body</h1>" > /w/probe.html' >/dev/null 2>&1 || true
# Basic Auth가 걸려 있으므로 자격증명을 함께 보낸다.
body_contains "확장자 없는 /probe가 probe.html로 해석" \
  "notes.${base_domain}" "/probe" "note body" -u test:test

echo "--- 잘못된 서비스 이름은 502 ---"
# spec 사용자 스토리 4: 서비스 이름/포트 오타를 로컬에서 502로 본다.
# jenkins는 별도 compose가 띄우므로 로컬 기본 스택에서는 502가 정상이다.
check "미기동 upstream은 502" "jenkins.${base_domain}" / 502

if [ "$fail" -ne 0 ]; then
  echo "seam 2: FAILED" >&2
  exit 1
fi
echo "seam 2: all passed"
