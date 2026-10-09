#!/usr/bin/env bash
# seam 2 검증. 기동된 스택에 실제 HTTP 요청을 보내 상태 코드와 본문을 본다.
#
# 렌더된 conf를 검사하지 않는 이유: 200 응답 하나가 템플릿 렌더·라우팅·
# 네트워크 연결을 동시에 증명한다. conf 내용을 diff하면 구현을 바꿀 때마다 깨진다.
#
# 전제: docker compose up -d 가 이미 완료된 상태.
#   BASE_URL 로 대상 변경 가능 (기본 http://127.0.0.1)
#
# notes 자격증명은 환경변수로 받는다. 기본값은 공개 fixture(test/test)이며,
# 실제 secret(secrets/basic-auth.htpasswd)을 마운트한 상태에서 검증하려면
# NOTES_USER / NOTES_PASS 를 넘긴다. 하드코딩하면 secret을 바꾼 뒤 깨진다.
set -euo pipefail

base_url="${BASE_URL:-http://127.0.0.1}"
base_domain="${BASE_DOMAIN:-localhost}"
notes_user="${NOTES_USER:-test}"
notes_pass="${NOTES_PASS:-test}"

# 스킴에 따라 요청 방식이 다르다.
#   http  (로컬): IP로 접속하고 Host 헤더로 서브도메인을 지정한다.
#                 로컬은 인증서가 없으므로 이 방식이 필요하다.
#   https (VPS):  호스트명으로 직접 접속한다. IP+Host 헤더로는 SNI가
#                 인증서 이름과 맞지 않아 TLS 핸드셰이크가 실패한다(코드 000).
scheme="${base_url%%://*}"

# 요청 인자를 스킴에 맞게 만든다. 호출부는 항상 전체 호스트명을 넘긴다.
# 결과를 전역 REQ 배열에 담는다(bash 3.2 호환을 위해 반환값 대신 전역 사용).
build_req() {
  local host="$1" path="$2"
  if [ "$scheme" = "https" ]; then
    REQ=("https://${host}${path}")
  else
    REQ=(-H "Host: ${host}" "${base_url}${path}")
  fi
}

fail=0

# check <설명> <호스트명> <경로> <기대 상태코드> [curl 추가인자...]
check() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  build_req "$host" "$path"
  local got
  got="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    "$@" "${REQ[@]}" || true)"
  if [ "$got" = "$want" ]; then
    echo "ok   - $desc ($host$path -> $got)"
  else
    echo "FAIL - $desc: $host$path want $want, got $got" >&2
    fail=1
  fi
}

# body_contains <설명> <호스트명> <경로> <기대 문자열> [curl 추가인자...]
body_contains() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  build_req "$host" "$path"
  local body
  body="$(curl -s --connect-timeout 5 --max-time 15 \
    "$@" "${REQ[@]}" || true)"
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
# 등록 안 된 Host는 444(응답 없이 끊김)라 curl은 000을 본다.
check "등록 안 된 Host는 연결을 끊는다" "unknown.invalid" / 000

echo "--- Basic Auth ---"
# 자격증명 없이 401이어야 한다. 200이면 인증이 빠진 것.
check "notes 인증 없이 401" "notes.${base_domain}" / 401
# 틀린 비밀번호도 401이어야 한다. 여기서 500이 나오면 nginx가 htpasswd 파일을
# 읽지 못하는 것이다(파일 권한 600 + nginx 워커가 비-root인 경우).
# 401과 500을 구분하지 않으면 이 권한 문제가 테스트를 통과해버린다.
check "notes 틀린 비밀번호도 401" "notes.${base_domain}" / 401 -u "${notes_user}:definitely-wrong"
# 올바른 자격증명으로는 통과해야 한다.
# 콘텐츠가 없으면 404, 있으면 200 — 둘 다 인증 통과를 뜻한다.
build_req "notes.${base_domain}" "/"
got="$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 \
  -u "${notes_user}:${notes_pass}" "${REQ[@]}" || echo 000)"
if [ "$got" = "200" ] || [ "$got" = "404" ]; then
  echo "ok   - notes 올바른 자격증명으로 인증 통과 ($got)"
else
  echo "FAIL - notes 자격증명 통과 실패: got $got" >&2
  fail=1
fi

echo "--- 정적 사이트 try_files ---"
# 확장자 없는 경로가 .html로 해석되는지. probe 파일을 볼륨에 넣어 확인한다.
# nginx는 /var/www/notes를 :ro로 마운트하므로 쓰기는 별도 컨테이너로 한다.
docker run --rm -v "${QUARTZ_VOLUME:-vps_quartz_site}":/w alpine:3.24 \
  sh -c 'echo "<h1>note body</h1>" > /w/probe.html' >/dev/null 2>&1 || true
# Basic Auth가 걸려 있으므로 자격증명을 함께 보낸다.
body_contains "확장자 없는 /probe가 probe.html로 해석" \
  "notes.${base_domain}" "/probe" "note body" -u "${notes_user}:${notes_pass}"

echo "--- ERD 정적 서빙 (하위 경로) ---"
# erd-site 볼륨에 /probe 프로젝트 폴더를 만들고 Liam 산출물과 같은 모양(index.html, schema.json)을 넣는다.
docker run --rm -v "${ERD_VOLUME:-vps_erd_site}":/w alpine:3.24 \
  sh -c 'mkdir -p /w/probe && echo "<h1>erd body</h1>" > /w/probe/index.html && echo "{\"tables\":{}}" > /w/probe/schema.json' >/dev/null 2>&1 || true
check "erd 인증 없이 401" "erd.${base_domain}" /probe/ 401
body_contains "erd /probe/ 가 index.html 서빙" \
  "erd.${base_domain}" "/probe/" "erd body" -u "${notes_user}:${notes_pass}"
body_contains "erd /probe/schema.json 서빙" \
  "erd.${base_domain}" "/probe/schema.json" "tables" -u "${notes_user}:${notes_pass}"
# 슬래시 없는 경로는 nginx가 슬래시를 붙여 redirect한다.
check "erd /probe 는 /probe/ 로 redirect" "erd.${base_domain}" /probe 301 -u "${notes_user}:${notes_pass}"
# 파일명이 고정인 json은 캐시되면 갱신이 안 보인다.
build_req "erd.${base_domain}" "/probe/schema.json"
if curl -sI --connect-timeout 5 --max-time 15 -u "${notes_user}:${notes_pass}" "${REQ[@]}" \
   | grep -qi '^cache-control: no-cache'; then
  echo "ok   - erd schema.json은 no-cache"
else
  echo "FAIL - erd schema.json에 Cache-Control: no-cache가 없다" >&2
  fail=1
fi

echo "--- 별도 compose 프로젝트 라우팅 ---"
# jenkins는 jenkins/compose.yml이 띄우므로 이 스택만으로는 없을 수 있다.
# 어느 쪽이든 "nginx가 기동되어 이 server 블록을 처리한다"가 증명되어야 한다.
#   502 = Jenkins 미기동 (upstream 해석 실패 -> 변수+resolver가 동작한 것)
#   403/200 = Jenkins 기동 (인증 요구 또는 응답)
# 여기서 000(연결 실패)이나 404가 나오면 라우팅이 깨진 것이다.
build_req "jenkins.${base_domain}" "/"
got="$(curl -s -o /dev/null -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 \
  "${REQ[@]}" || echo 000)"
case "$got" in
  502) echo "ok   - jenkins 미기동 상태에서 nginx는 정상 기동하고 502를 준다 ($got)" ;;
  200|403|401) echo "ok   - jenkins 기동 상태로 라우팅된다 ($got)" ;;
  *) echo "FAIL - jenkins 라우팅 실패: got $got (502 또는 200/403 기대)" >&2; fail=1 ;;
esac

if [ "$fail" -ne 0 ]; then
  echo "seam 2: FAILED" >&2
  exit 1
fi
echo "seam 2: all passed"
