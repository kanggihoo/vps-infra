#!/usr/bin/env bash
# seam 1 검증. 가짜 git 레포를 만들어 select-target.sh의 stdout과 종료 코드를 본다.
# 프레임워크 없음. 실패하면 즉시 죽는다.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
select_target="$script_dir/select-target.sh"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

cd "$repo"
git init -q
git config user.email test@example.com
git config user.name test

fail=0

# expect <설명> <기대 stdout> <기대 exit> <before> <after>
expect() {
  local desc="$1" want_out="$2" want_code="$3" before="$4" after="$5"
  local got_out got_code
  set +e
  got_out="$("$select_target" "$before" "$after" 2>/dev/null)"
  got_code=$?
  set -e
  if [ "$got_out" = "$want_out" ] && [ "$got_code" = "$want_code" ]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc: want out='$want_out' code=$want_code, got out='$got_out' code=$got_code" >&2
    fail=1
  fi
}

# --- fixture: 커밋 4개 ---
mkdir -p portal
echo base > README.md
git add -A && git commit -qm base
base="$(git rev-parse HEAD)"

echo a > portal/App.tsx
git add -A && git commit -qm portal-only
portal_only="$(git rev-parse HEAD)"

echo b > compose.yml
echo c > portal/main.go
git add -A && git commit -qm mixed
mixed="$(git rev-parse HEAD)"

git commit -q --allow-empty -m empty
empty="$(git rev-parse HEAD)"

# Jenkins가 마지막 커밋만 보면 놓치는 실제 push 순서.
# nginx 변경 뒤 portal 변경이 따로 들어오면 누적 범위는 all이어야 한다.
mkdir -p nginx
echo nginx-change > nginx/site.conf
git add -A && git commit -qm infra-before-portal
infra_before_portal="$(git rev-parse HEAD)"

echo portal-after-infra > portal/App.tsx
git add -A && git commit -qm portal-after-infra
portal_after_infra="$(git rev-parse HEAD)"

# --- 검증 ---
expect "portal/ 아래만 바뀌면 portal" \
  portal 0 "$base" "$portal_only"

expect "portal/ 밖 파일이 섞이면 all" \
  all 0 "$portal_only" "$mixed"

expect "인프라 파일만 바뀌면 all" \
  all 0 "$base" "$mixed"

expect "최신 커밋만 보면 portal인 변경" \
  portal 0 "$infra_before_portal" "$portal_after_infra"

expect "누적 범위에 인프라 변경이 있으면 all" \
  all 0 "$empty" "$portal_after_infra"

# 핵심 결정: 빈 diff는 portal이 아니라 판정 불가다.
expect "변경 파일이 없으면 판정 불가로 실패" \
  "" 1 "$mixed" "$empty"

expect "존재하지 않는 리비전은 판정 불가로 실패" \
  "" 1 "$base" "does-not-exist"

expect "인자가 부족하면 사용법 오류" \
  "" 2 "$base" ""

if [ "$fail" -ne 0 ]; then
  echo "seam 1: FAILED" >&2
  exit 1
fi
echo "seam 1: all passed"
