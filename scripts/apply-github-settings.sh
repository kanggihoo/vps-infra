#!/usr/bin/env bash
# GitHub repository 설정과 main ruleset을 레포의 정의대로 적용한다.
# GitHub UI에서 바꾼 값은 이 스크립트를 다시 실행하면 덮어써진다.
#
# 사용: ./scripts/apply-github-settings.sh
# 필요: repo admin 권한으로 로그인한 `gh`
#
# ruleset 정의는 .github/rulesets/main.json에 있다.
#   - main 직접 push 금지(PR 필수), 승인 수 0(혼자 쓰는 repo는 자기 PR을 승인할 수 없다)
#   - `ci / gate` 필수, branch가 최신 main을 포함해야 merge 가능(strict)
#   - squash merge만 허용, force push·삭제 금지
#   - repository admin은 PR을 통해서만 우회할 수 있다
# `integration_id` 15368은 GitHub Actions app이다. 다른 app이 같은 이름의 check를 보고해도 인정하지 않는다.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO=${REPO:-kanggihoo/vps-infra}
RULESET_FILE=.github/rulesets/main.json
RULESET_NAME=$(jq -r .name "$RULESET_FILE")

echo "[settings] $REPO merge 설정을 적용한다"
# squash만 남기고, squash 메시지는 PR 제목과 본문을 쓴다.
# merge 후 head branch를 지우고, out-of-date PR에 Update branch 버튼을 항상 보인다.
gh api -X PATCH "repos/$REPO" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY >/dev/null

id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")
if [[ -n "$id" ]]; then
  echo "[settings] ruleset '$RULESET_NAME'($id)을 갱신한다"
  gh api -X PUT "repos/$REPO/rulesets/$id" --input "$RULESET_FILE" >/dev/null
else
  echo "[settings] ruleset '$RULESET_NAME'을 만든다"
  gh api -X POST "repos/$REPO/rulesets" --input "$RULESET_FILE" >/dev/null
fi

echo "[settings] 완료"
