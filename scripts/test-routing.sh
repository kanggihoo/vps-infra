#!/usr/bin/env bash
# seam 2 검증. 기동된 스택에 실제 HTTP 요청을 보내 상태 코드와 본문을 본다.
#
# 렌더된 conf를 검사하지 않는 이유: 응답 하나가 템플릿 렌더·라우팅·
# 네트워크 연결을 동시에 증명한다. conf 내용을 diff하면 구현을 바꿀 때마다 깨진다.
#
# 전제: docker compose up -d 가 이미 완료된 상태. 관측 스택(grafana)도 떠 있어야 한다.
#   docker compose -f observability/compose.yml --env-file .env up -d
#
# 요청은 실제 호스트명으로 보내고 curl --resolve로 연결 IP만 바꾼다. 쿠키가 도메인 규칙대로
# 저장·전송되어야 브라우저와 같은 SSO 경로를 검증할 수 있다(Host 헤더 방식은 쿠키 jar가 IP에 묶인다).
#   SCHEME       http(기본, 로컬) | https(VPS)
#   CONNECT_IP   127.0.0.1(기본)
#   BASE_DOMAIN  vps.localhost(기본)
#   AUTH_USER / AUTH_PASS  Tinyauth 로컬 계정. 기본값은 공개 테스트 계정(test/test)
set -euo pipefail

cd "$(dirname "$0")/.."

scheme="${SCHEME:-http}"
connect_ip="${CONNECT_IP:-127.0.0.1}"
base_domain="${BASE_DOMAIN:-vps.localhost}"
auth_user="${AUTH_USER:-test}"
auth_pass="${AUTH_PASS:-test}"
port=80
[ "$scheme" = https ] && port=443

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
jar="$work/cookies.txt"

fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*" >&2; fail=1; }

# req <호스트명> <경로> [curl 추가인자...]  응답 본문을 stdout으로 낸다.
req() {
  local host="$1" path="$2"
  shift 2
  curl -s --connect-timeout 5 --max-time 15 \
    --resolve "${host}:${port}:${connect_ip}" "$@" "${scheme}://${host}${path}" || true
}

# code <호스트명> <경로> [curl 추가인자...]  "<상태코드> <Location>"
code() {
  local host="$1" path="$2"
  shift 2
  req "$host" "$path" -o /dev/null -w '%{http_code} %{redirect_url}' "$@"
}

# check <설명> <호스트명> <경로> <기대 상태코드 정규식> [curl 추가인자...]
check() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  local got
  got="$(code "$host" "$path" "$@")"
  if [[ "${got%% *}" =~ ^(${want})$ ]]; then
    ok "$desc ($host$path -> ${got%% *})"
  else
    bad "$desc: $host$path want $want, got ${got%% *}"
  fi
}

# body_contains <설명> <호스트명> <경로> <기대 문자열> [curl 추가인자...]
body_contains() {
  local desc="$1" host="$2" path="$3" want="$4"
  shift 4
  if req "$host" "$path" "$@" | grep -qF -- "$want"; then
    ok "$desc"
  else
    bad "$desc: '$want' not found in response body"
  fi
}

# login_redirect <설명> <호스트명> <경로> [curl 추가인자...]
#   미인증 요청이 auth 로그인 URL로 302 되는지. redirect_uri가 원래 주소를 담는지도 본다.
login_redirect() {
  local desc="$1" host="$2" path="$3"
  shift 3
  local got want="302 ${scheme}://auth.${base_domain}/login?redirect_uri=${scheme}://${host}${path}"
  got="$(code "$host" "$path" "$@")"
  if [ "$got" = "$want" ]; then
    ok "$desc ($host$path -> 302 login)"
  else
    bad "$desc: $host$path want '$want', got '$got'"
  fi
}

ws=(-H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==")

echo "--- probe 파일 준비 ---"
# nginx는 정적 볼륨을 :ro로 마운트하므로 쓰기는 별도 컨테이너로 한다.
docker run --rm -v "${QUARTZ_VOLUME:-vps_quartz_site}":/w alpine:3.24 \
  sh -c 'echo "<h1>note body</h1>" > /w/probe.html && echo "body{}" > /w/probe.css && echo "<h1>quartz 404</h1>" > /w/404.html' >/dev/null
docker run --rm -v "${ERD_VOLUME:-vps_erd_site}":/w alpine:3.24 \
  sh -c 'mkdir -p /w/probe && echo "<h1>erd body</h1>" > /w/probe/index.html && echo "{\"tables\":{}}" > /w/probe/schema.json' >/dev/null

echo "--- 공개 서브도메인 ---"
check "portal은 인증 없이 200" "portal.${base_domain}" / 200
check "health -> whoami" "health.${base_domain}" / 200
body_contains "whoami 응답 본문 확인" "health.${base_domain}" / "Hostname"
check "auth 로그인 포털은 인증 없이 200" "auth.${base_domain}" / 200
# 등록 안 된 Host는 444(응답 없이 끊김)라 curl은 000을 본다.
check "등록 안 된 Host는 연결을 끊는다" "unknown.invalid" / 000

echo "--- 미인증 요청은 어떤 경로도 200이 아니라 로그인으로 302 ---"
login_redirect "erd 루트" "erd.${base_domain}" /
login_redirect "erd 하위 경로" "erd.${base_domain}" /probe/
login_redirect "erd 정적 자산(json)" "erd.${base_domain}" /probe/schema.json
login_redirect "notes 루트" "notes.${base_domain}" /
login_redirect "notes 노트" "notes.${base_domain}" /probe
login_redirect "notes 정적 자산(css)" "notes.${base_domain}" /probe.css
login_redirect "notes /404.html" "notes.${base_domain}" /404.html
login_redirect "notes 없는 경로(404 페이지)" "notes.${base_domain}" /no-such-note
login_redirect "info 루트" "info.${base_domain}" /
login_redirect "grafana 루트" "grafana.${base_domain}" /
login_redirect "grafana /api/health" "grafana.${base_domain}" /api/health
login_redirect "grafana /api/live/ WebSocket" "grafana.${base_domain}" /api/live/ws "${ws[@]}"

echo "--- 헤더 위조로 우회할 수 없다 ---"
# nginx가 X-Forwarded-Host를 $host로 덮어쓰므로, 공개 서브도메인인 척해도 erd 인증을 묻는다.
login_redirect "X-Forwarded-Host 위조는 무시된다" "erd.${base_domain}" /probe/ \
  -H "X-Forwarded-Host: portal.${base_domain}" -H "X-Forwarded-Uri: /"
# Grafana는 Remote-User를 믿는다. 미인증 요청이 보낸 Remote-User/Authorization으로는 들어갈 수 없다.
login_redirect "Remote-User 위조는 인증을 대신하지 못한다" "grafana.${base_domain}" /api/user \
  -H "Remote-User: admin"
login_redirect "Grafana Basic Auth 헤더는 인증을 대신하지 못한다" "grafana.${base_domain}" /api/user \
  -u "admin:${GRAFANA_ADMIN_PASSWORD:-x}"
# /tinyauth는 internal이다. 외부에서 직접 부르면 200이 아니어야 한다(404 -> notes는 404 페이지도 인증 뒤).
for h in erd notes info grafana; do
  check "$h /tinyauth 외부 직접 호출 차단" "$h.${base_domain}" /tinyauth "404|302"
done

echo "--- 로컬 계정 로그인 -> 쿠키 세션 ---"
login_headers="$(req "auth.${base_domain}" /api/user/login -D - -o /dev/null -c "$jar" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"${auth_user}\",\"password\":\"${auth_pass}\"}")"
cookie_line="$(printf '%s' "$login_headers" | grep -i '^set-cookie: tinyauth-session' || true)"
if [ -n "$cookie_line" ]; then
  ok "로그인 성공, 세션 쿠키 발급"
else
  bad "로그인 실패: Set-Cookie tinyauth-session 없음"
fi
# 쿠키는 상위 도메인에 걸려야 다른 서브도메인으로 전송된다.
if printf '%s' "$cookie_line" | grep -qiF "Domain=${base_domain};"; then
  ok "세션 쿠키 Domain=${base_domain}"
else
  bad "세션 쿠키 Domain이 ${base_domain}이 아니다: $cookie_line"
fi
# 24시간(86400초). 발급 시각과의 반올림으로 86399가 올 수 있다.
if printf '%s' "$cookie_line" | grep -qE 'Max-Age=(86400|86399);'; then
  ok "세션 쿠키 Max-Age 24시간"
else
  bad "세션 쿠키 Max-Age가 24시간이 아니다: $cookie_line"
fi
bad_login="$(code "auth.${base_domain}" /api/user/login -H 'Content-Type: application/json' \
  --data "{\"username\":\"${auth_user}\",\"password\":\"definitely-wrong\"}")"
if [ "${bad_login%% *}" = 401 ]; then
  ok "틀린 비밀번호는 401"
else
  bad "틀린 비밀번호: want 401, got ${bad_login%% *}"
fi

authed_checks() {
  local tag="$1"
  body_contains "[$tag] erd /probe/ 가 index.html 서빙" "erd.${base_domain}" /probe/ "erd body" -b "$jar"
  body_contains "[$tag] erd /probe/schema.json 서빙" "erd.${base_domain}" /probe/schema.json "tables" -b "$jar"
  check "[$tag] erd /probe 는 /probe/ 로 redirect" "erd.${base_domain}" /probe 301 -b "$jar"
  body_contains "[$tag] notes 확장자 없는 /probe가 probe.html로 해석" "notes.${base_domain}" /probe "note body" -b "$jar"
  check "[$tag] notes 정적 자산" "notes.${base_domain}" /probe.css 200 -b "$jar"
  body_contains "[$tag] notes 없는 경로는 Quartz 404 페이지" "notes.${base_domain}" /no-such-note "quartz 404" -b "$jar"
  # vps-info는 자기 레포 compose로 뜬다. 없으면 502이고, 이것도 인증을 통과해 백엔드까지 갔다는 뜻이다.
  check "[$tag] info 인증 통과" "info.${base_domain}" / "200|502" -b "$jar"
  check "[$tag] grafana 인증 통과" "grafana.${base_domain}" / 200 -b "$jar"
  # 로그인 상태에서도 /tinyauth는 internal이라 404다. internal;이 빠지면 Tinyauth 응답(200)이 그대로 나간다.
  # 미인증 호출은 auth_request가 먼저 302로 막으므로 internal;은 로그인 상태에서만 드러난다.
  for h in erd notes info grafana; do
    check "[$tag] $h /tinyauth는 로그인 상태에서도 404" "$h.${base_domain}" /tinyauth 404 -b "$jar"
  done
}

echo "--- 같은 쿠키로 보호 대상 4곳 통과 ---"
authed_checks "로그인"
if cache_headers="$(req "erd.${base_domain}" /probe/schema.json -I -b "$jar")" &&
   printf '%s' "$cache_headers" | grep -qi '^cache-control: no-cache'; then
  ok "erd schema.json은 no-cache"
else
  bad "erd schema.json에 Cache-Control: no-cache가 없다"
fi

echo "--- Grafana Auth Proxy ---"
# Grafana가 보는 사용자는 Tinyauth가 정한 사람이다. 클라이언트가 보낸 Remote-User는 덮어써진다.
body_contains "Grafana 사용자는 Tinyauth 로그인 사용자" "grafana.${base_domain}" /api/user "\"login\":\"${auth_user}\"" \
  -b "$jar" -H "Remote-User: admin"
body_contains "Grafana 자동 가입 사용자는 Admin" "grafana.${base_domain}" /api/user/orgs '"role":"Admin"' -b "$jar"
# Authorization을 nginx가 비우므로 admin 비밀번호를 보내도 admin이 되지 않는다.
body_contains "Grafana Authorization 헤더는 비워진다" "grafana.${base_domain}" /api/user "\"login\":\"${auth_user}\"" \
  -b "$jar" -u "admin:${GRAFANA_ADMIN_PASSWORD:-x}"
check "grafana /api/live/ WebSocket 인증 통과" "grafana.${base_domain}" /api/live/ws 101 -b "$jar" "${ws[@]}" --max-time 3

echo "--- health는 세션 쿠키를 반사하지 않는다 ---"
health_body="$(req "health.${base_domain}" / -b "$jar")"
if printf '%s' "$health_body" | grep -q "Hostname" && ! printf '%s' "$health_body" | grep -qi 'tinyauth-session'; then
  ok "whoami 본문에 세션 쿠키가 없다"
else
  bad "whoami 본문에 세션 쿠키가 반사되었다(또는 응답 없음)"
fi

# 세션 DB가 named volume에 있으므로 컨테이너를 다시 만들어도 같은 쿠키가 유효해야 한다.
# 운영 컨테이너를 재생성하지 않도록 로컬(http)에서만 실행한다.
if [ "$scheme" = http ]; then
  echo "--- tinyauth 재생성 후 세션 유지 ---"
  docker compose up -d --force-recreate --no-deps tinyauth >/dev/null 2>&1
  for _ in $(seq 1 20); do
    [ "$(code "auth.${base_domain}" / | cut -d' ' -f1)" = 200 ] && break
    sleep 1
  done
  authed_checks "재생성 후"
fi

if [ "$fail" -ne 0 ]; then
  echo "seam 2: FAILED" >&2
  exit 1
fi
echo "seam 2: all passed"
