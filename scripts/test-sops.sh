#!/usr/bin/env bash
# seam 3 검증. 암호화 -> 복호화 왕복에서 기대한 키가 그대로 나오는지 본다.
# 목적은 key 배치 오류를 잡는 것이다.
#
# 이 테스트는 자기만의 임시 age key를 만든다. 실제 운영 key에 의존하지 않으므로
# key가 아직 없는 환경에서도 SOPS 배선 자체를 검증할 수 있다.
set -euo pipefail

for bin in sops age-keygen; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "[seam3] $bin 이 없다. tools 컨테이너에서 실행할 것:" >&2
    echo "  docker compose run --rm tools ./scripts/test-sops.sh" >&2
    exit 1
  }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 레포의 .sops.yaml을 쓰지 않는다. 이 테스트는 자기 임시 key로만 검증하므로
# 레포 설정(운영 age 수신자)이 끼면 "no matching creation rules"로 실패한다.
# 수신자는 아래에서 --age로 직접 지정하므로 규칙 파일 자체가 필요 없다.
# 임시 디렉터리로 이동해 상위 탐색이 레포 .sops.yaml에 닿지 않게 한다.
cd "$work"
# 모든 경로에 매칭되는 규칙을 둔다(수신자는 --age가 덮어쓴다).
# 빈 creation_rules는 "매칭 규칙 없음"이 되어 오히려 실패한다.
printf 'creation_rules:\n  - path_regex: .*\n' > "$work/.sops.yaml"
export SOPS_CONFIG="$work/.sops.yaml"

# --- 임시 key 생성 ---
key="$work/keys.txt"
age-keygen -o "$key" 2>/dev/null
recipient="$(grep -o 'age1[0-9a-z]*' "$key" | head -1)"

export SOPS_AGE_KEY_FILE="$key"

fail=0

# --- 왕복 1: .env 형태 (key=value) ---
cat > "$work/plain.env" <<'EOF'
POSTGRES_PASSWORD=roundtrip-secret-value
REDIS_PASSWORD=another-secret
EOF

sops --encrypt --age "$recipient" "$work/plain.env" > "$work/enc.sops.env"

# 암호문에 평문 값이 남아 있으면 안 된다.
if grep -q 'roundtrip-secret-value' "$work/enc.sops.env"; then
  echo "FAIL - 암호화 파일에 평문 값이 남아 있다" >&2
  fail=1
else
  echo "ok   - 암호화 파일에 평문이 없다"
fi

# 복호화 결과가 원본과 같아야 한다.
sops --decrypt "$work/enc.sops.env" > "$work/out.env"
if diff -q "$work/plain.env" "$work/out.env" >/dev/null; then
  echo "ok   - .env 왕복이 원본과 일치"
else
  echo "FAIL - .env 왕복 결과가 원본과 다르다" >&2
  fail=1
fi

# 기대한 키가 실제로 나오는지 확인한다.
if grep -q '^POSTGRES_PASSWORD=roundtrip-secret-value$' "$work/out.env"; then
  echo "ok   - 기대한 키가 복호화되어 나온다"
else
  echo "FAIL - 복호화 결과에 기대한 키가 없다" >&2
  fail=1
fi

# --- 왕복 2: htpasswd 형태 (구조 없는 텍스트) ---
printf 'test:$2y$05$abcdefghijklmnopqrstuv\n' > "$work/plain.htpasswd"
sops --encrypt --age "$recipient" "$work/plain.htpasswd" > "$work/enc.htpasswd.sops"
sops --decrypt "$work/enc.htpasswd.sops" > "$work/out.htpasswd"
if diff -q "$work/plain.htpasswd" "$work/out.htpasswd" >/dev/null; then
  echo "ok   - htpasswd 왕복이 원본과 일치"
else
  echo "FAIL - htpasswd 왕복 결과가 원본과 다르다" >&2
  fail=1
fi

# --- key 배치 오류 검증: 틀린 key로는 복호화가 실패해야 한다 ---
wrong="$work/wrong.txt"
age-keygen -o "$wrong" 2>/dev/null
if SOPS_AGE_KEY_FILE="$wrong" sops --decrypt "$work/enc.sops.env" >/dev/null 2>&1; then
  echo "FAIL - 틀린 key로 복호화가 성공했다" >&2
  fail=1
else
  echo "ok   - 틀린 key로는 복호화가 실패한다"
fi

if [ "$fail" -ne 0 ]; then
  echo "seam 3: FAILED" >&2
  exit 1
fi
echo "seam 3: all passed"
