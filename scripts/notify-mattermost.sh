#!/usr/bin/env bash
# 배포 결과를 Mattermost로 알린다(ADR 0012). `main.yml`과 `redeploy.yml`의 notify job이 호출한다.
#
# 입력은 모두 환경변수로 받는다. 커밋 메시지 같은 사용자 입력을 workflow의 run에
# ${{ }}로 넣으면 셸 코드로 해석될 수 있으므로, workflow는 env로만 넘긴다.
#
#   HOOK            Mattermost incoming webhook URL. 비어 있으면 알림을 건너뛴다.
#   CI, PUBLISH     해당 job의 result. 그 job이 없는 workflow는 비워 둔다.
#   DEPLOY          deploy job의 result. success일 때만 성공으로 알린다.
#   TARGET          요청한 배포 대상.
#   COMMIT_MESSAGE  push한 커밋 메시지. 수동 재배포에서는 비어 있다.
#   ACTOR, COMMIT_URL, RUN_URL, GITHUB_SHA
set -uo pipefail

if [[ -z "${HOOK:-}" ]]; then
  echo "[notify] MATTERMOST_WEBHOOK_URL이 없어 알림을 건너뛴다"
  exit 0
fi

ok=0
[[ "${DEPLOY:-}" == success ]] && ok=1

# 실패한 첫 단계를 고른다. 비어 있는 단계는 그 workflow에 없는 job이다.
stage=deploy
if [[ -n "${CI:-}" && "$CI" != success ]]; then
  stage=ci
elif [[ "${PUBLISH:-}" == failure ]]; then
  stage=publish
fi

subject="${COMMIT_MESSAGE:-}"
subject="${subject%%$'\n'*}"
if [[ "$ok" == 1 ]]; then
  title="배포 성공 · vps-infra main"
  text="${subject:-수동 재배포}"
  color='#2eb886'
else
  title="배포 실패 · vps-infra main"
  text="${subject:-수동 재배포} · 실패 단계: ${stage}. 로그: ${RUN_URL}"
  color='#d33f3f'
fi

jq -n --arg title "$title" --arg link "$RUN_URL" --arg color "$color" --arg text "$text" \
  --arg commit "[\`${GITHUB_SHA::7}\`](${COMMIT_URL})" --arg actor "$ACTOR" --arg target "$TARGET" \
  '{username: "GitHub Actions", attachments: [{color: $color, title: $title, title_link: $link, text: $text,
    fields: [{short: true, title: "커밋", value: $commit}, {short: true, title: "실행자", value: $actor},
             {short: true, title: "요청 대상", value: $target}]}]}' |
  curl -fsS --max-time 10 -H 'Content-Type: application/json' -d @- "$HOOK" >/dev/null ||
  echo "[notify] 알림 전송 실패(결과에는 영향 없음)"
