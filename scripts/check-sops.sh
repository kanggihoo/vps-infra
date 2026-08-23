#!/usr/bin/env bash
# SOPS 파일 무결성 검증. key가 없어도 동작하므로 CI에서 쓸 수 있다.
#
# 확인하는 것: secrets/*.sops.* 가 실제로 암호화되어 있는가.
# 파일명이 .sops.env / .sops.txt인 이유는 scripts/secrets.sh 주석 참고.
# 평문을 실수로 커밋하는 사고를 잡는 것이 목적이다.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
found=0

for f in secrets/*.sops.*; do
  [ -e "$f" ] || continue
  found=$((found + 1))
  # SOPS 파일에는 항상 sops 메타데이터 블록이 있다. 없으면 평문이다.
  if grep -q '"sops"\|^sops:\|sops_version' "$f" 2>/dev/null; then
    echo "ok   - $f 는 암호화되어 있다"
  else
    echo "FAIL - $f 에 sops 메타데이터가 없다 (평문 커밋 의심)" >&2
    fail=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[check-sops] secrets/*.sops.* 파일이 없다 (아직 도입 전이면 정상)"
  exit 0
fi

# 평문 secret이 실수로 커밋 대상에 들어갔는지 확인한다.
for leak in .env secrets/notes.htpasswd secrets/github-pat; do
  if git ls-files --error-unmatch "$leak" >/dev/null 2>&1; then
    echo "FAIL - 평문 secret이 git에 추적되고 있다: $leak" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] || { echo "check-sops: FAILED" >&2; exit 1; }
echo "check-sops: ok"
