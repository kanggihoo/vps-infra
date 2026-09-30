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
# 환경별 .env를 한 벌씩 둔다. 로컬과 VPS는 도메인·TLS 모드가 다르고
# DB 비밀번호도 다르므로 파일 하나로 합칠 수 없다.
# 환경을 늘릴 때는 secrets/env.<이름>.sops.env를 추가하면 된다(spec 사용자 스토리 14).
#   ENV_NAME=local (기본) | prod
env_name="${ENV_NAME:-local}"

declare -A TARGETS=(
  ["secrets/env.${env_name}.sops.env"]=".env"
  ["secrets/basic-auth.htpasswd.sops.txt"]="secrets/basic-auth.htpasswd"
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

    # 기본은 600(소유자만). 단 컨테이너가 비-root 사용자로 읽어야 하는
    # 파일은 644로 둔다.
    #   htpasswd: nginx 워커가 `nginx` 사용자로 실행되므로 600이면
    #   "open() ... failed (13: Permission denied)"로 500을 응답한다.
    #   내용은 단방향 해시(apr1/bcrypt)이고 이미 이미지 안에서만 보이므로
    #   644가 실질적 노출을 늘리지 않는다.
    case "$dst" in
      *htpasswd) chmod 644 "$dst" ;;
      *)         chmod 600 "$dst" ;;
    esac
    # tools 컨테이너는 root로 동작하므로 결과가 root:root 600이 된다.
    # 그러면 호스트 사용자가 읽지 못해 compose가 .env를 못 읽는다.
    # HOST_UID/GID가 주어지면 소유권을 호스트 사용자에게 넘긴다.
    if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
      chown "${HOST_UID}:${HOST_GID}" "$dst" 2>/dev/null || true
    fi
    echo "[secrets] $src -> $dst"
  done
  [ "$missing" -eq 0 ] || echo "[secrets] 일부 파일이 아직 암호화되지 않았다" >&2
}

cmd_encrypt() {
  local plain="${1:?usage: secrets.sh encrypt <평문파일> <대상.sops>}"
  local out="${2:?usage: secrets.sh encrypt <평문파일> <대상.sops>}"
  require_key

  # 형식을 출력 파일명으로 판단해 명시적으로 넘긴다.
  # 이유: .sops.yaml의 creation_rules는 **입력 파일명**에 매칭되므로,
  # 평문 임시 파일 이름이 무엇이냐에 따라 dotenv 대신 binary/json 규칙이
  # 잡히는 사고가 난다(예: secrets/.env.prod.tmp -> JSON으로 암호화되어
  # 복호화 시 "invalid dotenv input line: {" 로 실패).
  local fmt=()
  case "$out" in
    *.env) fmt=(--input-type dotenv --output-type dotenv) ;;
    *)     fmt=(--input-type binary --output-type binary) ;;
  esac
  mkdir -p "$(dirname "$out")"
  sops --encrypt "${fmt[@]}" "$plain" > "$out"
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
