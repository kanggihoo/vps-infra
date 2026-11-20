#!/usr/bin/env bash
# 운영 VPS 배포 진입점. GitHub Actions가 SSH로 부른다(ADR 0020). Jenkinsfile이 하던 일을 순서대로 한다.
#
#   SSH  authorized_keys: command="/home/kkh/app/vps-infra/scripts/ci-deploy.sh",restrict ssh-ed25519 ... vps-infra-deploy
#        Actions는 `ssh kkh@<VPS> "<sha> [target]"`를 보내고, 그 문자열은 SSH_ORIGINAL_COMMAND로 들어온다.
#   수동 ~/app/vps-infra/scripts/ci-deploy.sh <sha> [auto|all|portal|observability]
#
# <sha>     배포할 main 커밋(40자). checkout을 이 커밋으로 맞춘다. 롤백은 이전 main SHA를 넘긴다.
# target    auto(기본) = 마지막 성공 배포부터의 누적 변경으로 판정(select-target.sh). 판정할 수 없으면 실패한다.
#           all|portal|observability = 판정을 건너뛰고 그 대상으로 배포한다(재배포, 롤백).
#
# 판정·배포·검사 로직은 select-target.sh, secrets.sh, deploy.sh, healthcheck.sh에 있고 여기는 순서만 정한다.
# 전체를 { }로 감싼 이유: 아래 git checkout이 실행 중인 이 파일을 바꿔도 bash는 이미 다 읽은 내용으로 끝까지 실행한다.
{
set -euo pipefail

# SSH로 온 문자열은 외부 입력이다. 셸로 해석하지 않고 형식만 허용한다.
read -r sha target extra <<<"${SSH_ORIGINAL_COMMAND-$*}" || true
target="${target:-auto}"
if ! [[ "${sha:-}" =~ ^[0-9a-f]{40}$ ]] || [[ -n "${extra:-}" ]]; then
    echo "usage: ci-deploy.sh <40자 commit sha> [auto|all|portal|observability]" >&2
    exit 2
fi
case "$target" in
    auto | all | portal | observability) ;;
    *) echo "usage: ci-deploy.sh <40자 commit sha> [auto|all|portal|observability]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."

# 다른 프로젝트 배포(vps-info scripts/deploy.sh)와 같은 lock이다. VPS에서 배포는 한 번에 하나만 돈다.
exec 9>/tmp/vps-deploy.lock
flock -w 900 9 || { echo "[ci-deploy] 다른 배포가 15분 넘게 끝나지 않는다" >&2; exit 1; }

# main 이력의 커밋만 배포한다. 배포 key가 새도 main에 없는 코드는 올릴 수 없다.
git fetch --quiet origin main
if ! git merge-base --is-ancestor "$sha" origin/main; then
    echo "[ci-deploy] $sha 는 origin/main 이력에 없다" >&2
    exit 1
fi
# reset --hard가 아니라 checkout이다. 운영 checkout에 손으로 고친 tracked 파일이 있으면 덮어쓰지 않고 멈춘다.
git checkout --quiet --detach "$sha"
echo "[ci-deploy] $(git log -1 --format='%h %s')"

# 마지막 성공 배포부터 이번 SHA까지의 누적 변경을 본다. 상태가 없거나 이력이 끊기면 일부 변경을 놓치지 않도록 all을 고른다.
state_file=.deploy-state/last-successful-sha
if [ "$target" = auto ]; then
    previous_sha="$(cat "$state_file" 2>/dev/null || true)"
    if [[ "$previous_sha" =~ ^[0-9a-f]{40}$ ]] && git merge-base --is-ancestor "$previous_sha" "$sha" 2>/dev/null; then
        target="$(./scripts/select-target.sh "$previous_sha" "$sha")"
    else
        echo "[ci-deploy] 마지막 성공 배포 SHA가 없거나 이번 커밋의 조상이 아니다. 전체를 배포한다" >&2
        target=all
    fi
fi
echo "[ci-deploy] target: $target"
echo "::notice title=배포 대상::$target"

# 커밋된 SOPS 파일로 .env와 secret 파일을 다시 만든다. 운영 값의 원본은 레포다. VPS에서 .env를 직접 고치면 덮어써진다.
# sops는 호스트에 설치하지 않고 tools 이미지로 실행한다. key는 ~/.config/sops/age/keys.txt다.
HOST_UID="$(id -u)" HOST_GID="$(id -g)" ENV_NAME=prod \
    docker compose run --rm --no-deps -T tools ./scripts/secrets.sh decrypt

./scripts/deploy.sh "$target"

# 공개 DNS 대신 호스트의 nginx(443)로 바로 붙는다. 컨테이너가 VPS 공인 IP로 자기 자신에 못 붙는 hairpin 문제와 무관하다.
HEALTHCHECK_CONNECT_HOST=127.0.0.1 ./scripts/healthcheck.sh

# runtime state라 Git에 넣지 않는다. 임시 파일을 rename해 중간에 죽어도 깨진 SHA 파일을 남기지 않는다.
mkdir -p "$(dirname "$state_file")"
umask 077
printf '%s\n' "$sha" > "$state_file.tmp.$$"
mv "$state_file.tmp.$$" "$state_file"
echo "[ci-deploy] done $sha ($target)"
exit 0
}
