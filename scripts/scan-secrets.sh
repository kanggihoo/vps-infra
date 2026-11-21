#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=8.30.1
case "${1:-}" in
  staged)
    if [[ "$(gitleaks version)" != "$version" ]]; then
      echo "Install Gitleaks $version to run the pre-commit hook." >&2
      exit 1
    fi
    exec gitleaks git --staged --redact --no-banner .
    ;;
  ci)
    base="${2:-}"
    head="${3:?missing head}"
    git cat-file -e "$head^{commit}"
    range="$head"
    # A merge commit (PR) should include the PR base. A rewritten push history
    # may not, so scan the full reachable history when the range is uncertain.
    if [[ "$base" =~ ^[0-9a-f]{40}$ ]] && [[ "$base" != "$head" ]] &&
       git merge-base --is-ancestor "$base" "$head" 2>/dev/null; then
      range="$base..$head"
    fi
    exec docker run --rm -v "$PWD:/repo:ro" \
      -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/repo \
      "zricethezav/gitleaks:v$version" \
      git --redact --no-banner --log-opts="$range" /repo
    ;;
  *)
    echo "usage: $0 staged | ci <base> <head>" >&2
    exit 2
    ;;
esac
