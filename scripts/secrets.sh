#!/usr/bin/env bash
# SOPS secret 관리. tools 컨테이너에서 실행한다.
#
#   docker compose run --rm tools ./scripts/secrets.sh decrypt
#   docker compose run --rm tools ./scripts/secrets.sh encrypt <평문파일> <대상.sops>
#   docker compose run --rm tools ./scripts/secrets.sh edit <파일.sops>
#
# 복호화 key는 age 형식이며 ~/.config/sops/age/keys.txt에 둔다.
# 홈 디렉터리이므로 sudo가 필요 없다.
set -euo pipefail

cd "$(dirname "$0")/.."

# 암호화 파일 -> 복호화 결과 경로.
# 좌변은 커밋되고, 우변은 .gitignore로 제외된다.
#
# 암호화 파일이 `.sops.env` / `.sops.txt`로 끝나는 이유:
#   creation_rules(.sops.yaml)는 **암호화할 때만** 적용된다. 복호화할 때
#   SOPS는 규칙을 보지 않고 **파일 확장자**로 형식을 판단한다. 확장자가
#   `.sops`처럼 미지의 값이면 JSON으로 추측해 "invalid character '#'"로
#   실패한다. 따라서 SOPS가 아는 확장자를 유지해야 한다.
declare -A TARGETS=(
  ["secrets/env.sops.env"]=".env"
  ["secrets/notes.htpasswd.sops.txt"]="secrets/notes.htpasswd"
  ["secrets/github-pat.sops.txt"]="secrets/github-pat"
)

require_key() {
  local key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
  if [ ! -f "$key" ]; then
    echo "[secrets] age key not found: $key" >&2
    echo "[secrets] 생성: age-keygen -o \"$key\"" >&2
    exit 1
  fi
}

cmd_decrypt() {
  require_key
  local missing=0
  for src in "${!TARGETS[@]}"; do
    local dst="${TARGETS[$src]}"
    if [ ! -f "$src" ]; then
      echo "[secrets] skip (not yet encrypted): $src" >&2
      missing=1
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    sops --decrypt "$src" > "$dst"
    # secret 파일은 소유자만 읽게 한다.
    chmod 600 "$dst"
    echo "[secrets] $src -> $dst"
  done
  [ "$missing" -eq 0 ] || echo "[secrets] 일부 파일이 아직 암호화되지 않았다" >&2
}

cmd_encrypt() {
  local plain="${1:?usage: secrets.sh encrypt <평문파일> <대상.sops>}"
  local out="${2:?usage: secrets.sh encrypt <평문파일> <대상.sops>}"
  require_key
  mkdir -p "$(dirname "$out")"
  sops --encrypt "$plain" > "$out"
  echo "[secrets] encrypted $plain -> $out"
}

cmd_edit() {
  local file="${1:?usage: secrets.sh edit <파일.sops>}"
  require_key
  sops "$file"
}

case "${1:-}" in
  decrypt) cmd_decrypt ;;
  encrypt) shift; cmd_encrypt "$@" ;;
  edit)    shift; cmd_edit "$@" ;;
  *)
    echo "usage: $0 {decrypt|encrypt <plain> <out.sops>|edit <file.sops>}" >&2
    exit 2
    ;;
esac
