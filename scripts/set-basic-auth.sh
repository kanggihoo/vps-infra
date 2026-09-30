#!/usr/bin/env bash
# Basic Auth 계정을 secrets/basic-auth.htpasswd.sops.txt에 저장한다.
# 사용: ./scripts/set-basic-auth.sh <아이디> [비밀번호]
# 비밀번호를 생략하면 프롬프트로 받는다(셸 기록에 남지 않는다).
set -euo pipefail

user="${1:?사용: $0 <아이디> [비밀번호]}"
pw="${2:-}"
dst="secrets/basic-auth.htpasswd.sops.txt"

if [ -z "$pw" ]; then
  read -rsp "비밀번호: " pw; echo
fi
[ -n "$pw" ] || { echo "비밀번호가 비어 있다" >&2; exit 1; }

# 암호화는 공개키만 쓰지만, 마지막 검증에서 복호화하므로 key 위치를 잡아 준다.
# macOS의 sops는 앞 경로를, 그 밖에는 뒤 경로를 기본으로 본다.
if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  for k in "$HOME/Library/Application Support/sops/age/keys.txt" "$HOME/.config/sops/age/keys.txt"; do
    [ -f "$k" ] && { export SOPS_AGE_KEY_FILE="$k"; break; }
  done
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# apr1 해시. nginx auth_basic이 그대로 읽는다. 비밀번호는 stdin으로 넘겨 프로세스 목록에 노출하지 않는다.
printf '%s:%s\n' "$user" "$(printf '%s' "$pw" | openssl passwd -apr1 -stdin)" \
  | sops encrypt --filename-override "$dst" /dev/stdin > "$tmp"
mv "$tmp" "$dst"

echo "저장했다: $dst"
echo "확인한 아이디: $(sops decrypt "$dst" | cut -d: -f1)"
