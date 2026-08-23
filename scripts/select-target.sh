#!/usr/bin/env bash
# 배포 대상 판정. 부수효과 없음.
#
#   select-target.sh <before-rev> <after-rev>
#
# stdout  portal | all
# exit 0  판정 성공
# exit 1  판정 불가 (변경 파일 목록을 얻을 수 없음)
# exit 2  사용법 오류
#
# 판정 불가를 all로 떨어뜨리지 않는 이유:
#   빈 diff는 "변경이 없다"가 아니라 거의 항상 "변경을 알아낼 수 없었다"다
#   (첫 커밋, shallow clone, 잘못된 리비전, diff 명령 실패).
#   이를 portal로 해석하면 인프라 변경이 조용히 누락되고 빌드는 초록불로 끝난다.
#   판정 로직은 모를 때 모른다고 말해야 하고, 그 경우 배포 여부는 사람이 정한다.
#   의도적으로 배포하려면 deploy.sh에 대상을 직접 넘긴다(override).
set -euo pipefail

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: $0 <before-rev> <after-rev>" >&2
  exit 2
fi

before="$1"
after="$2"

# git이 실패하면(존재하지 않는 리비전 등) set -e로 죽지 않고 빈 문자열을 받는다.
# 판정 불가와 진짜 빈 diff를 여기서 구별하지 않는 것은 의도적이다. 둘 다 판정 불가다.
changed="$(git diff --name-only "$before" "$after" 2>/dev/null || true)"

if [ -z "$changed" ]; then
  echo "[select-target] cannot determine changed files between '$before' and '$after'" >&2
  echo "[select-target] pass the target explicitly to override (e.g. deploy.sh all)" >&2
  exit 1
fi

# portal/ 밖의 파일이 하나라도 있으면 전체 배포.
# grep -qv는 "매칭되지 않는 줄이 있는가"를 묻는다.
if printf '%s\n' "$changed" | grep -qv '^portal/'; then
  echo all
else
  echo portal
fi
