#!/usr/bin/env bash
# ==============================================================================
# Hostinger VPS 및 로컬 인프라 배포 스크립트 (scripts/deploy.sh)
#
# [실행 시점]
# 1. Jenkins CI/CD: main 브랜치 push 시 GitHub Webhook에 의해 자동 실행
#    (Jenkinsfile -> ./scripts/deploy.sh "$RESOLVED_TARGET")
# 2. 로컬 / 운영 수동 배포: 터미널에서 전체 스택 또는 특정 대상을 배포할 때 직접 실행
#
# [사용법]
#   ./scripts/deploy.sh [all|portal]
#   - all (기본값): 전체 인프라 스택 배포 (Nginx, DB, Redis, Portal 등)
#   - portal: 웹 애플리케이션(React/Go) 코드 변경 시 다른 인프라 중단 없이 Portal 단독 배포
# ==============================================================================

# 에러 발생 시 즉시 중단(-e), 정의되지 않은 변수 참조 시 중단(-u), 파이프라인 중간 에러 감지(-o pipefail)
set -euo pipefail

# 배포 대상 지정 (인자가 없으면 기본값은 'all')
target="${1:-all}"

# 스크립트 위치와 상관없이 저장소 루트 디렉터리로 이동
cd "$(dirname "$0")/.."

# ------------------------------------------------------------------------------
# 1. 대상 파라미터 유효성 검사
# ------------------------------------------------------------------------------
case "$target" in
  all|portal) ;;
  *)
    echo "[deploy] unknown target: $target" >&2
    echo "[deploy] usage: $0 [all|portal]" >&2
    exit 2
    ;;
esac

# ------------------------------------------------------------------------------
# 2. 필수 파일 존재 여부 확인
# ------------------------------------------------------------------------------
echo "[deploy] checking required files"
test -f .env
test -f compose.yml

# ------------------------------------------------------------------------------
# 3. .env 파일 유효성 검사 및 환경변수 로드
# ------------------------------------------------------------------------------
# .env를 셸로 읽는다. 공백이 든 값에 따옴표가 없으면 여기서
# "ssl: command not found"처럼 엉뚱한 오류가 나므로 미리 잡아준다.
# (예: NGINX_LISTEN=443 ssl 대신 NGINX_LISTEN="443 ssl" 이어야 함)
if grep -qE '^[A-Z_]+=[^"'"'"']*[[:space:]]' .env; then
  echo "[deploy] .env에 따옴표 없는 공백 값이 있다. 예: NGINX_LISTEN=\"443 ssl\"" >&2
  grep -nE '^[A-Z_]+=[^"'"'"']*[[:space:]]' .env | sed 's/=.*/=<...>/' >&2
  exit 2
fi

# .env의 환경변수들을 현재 셸 환경으로 export
set -a
. ./.env
set +a

# ------------------------------------------------------------------------------
# 4. 운영 환경(live TLS) 보안 안전장치
# ------------------------------------------------------------------------------
# live TLS에서 test/test fixture로 시작하면 notes 인증이 공개된다.
# 로컬 clean clone은 fixture를 계속 쓸 수 있고, 운영 진입점만 명확히 막는다.
if [ "${TLS_MODE:-none}" = "live" ] && \
   [ "${NOTES_HTPASSWD:-}" = "./nginx/test-fixtures/notes.htpasswd" ]; then
  echo "[deploy] TLS_MODE=live에서는 NOTES_HTPASSWD에 실제 secret 파일이 필요하다" >&2
  exit 2
fi

# ------------------------------------------------------------------------------
# 5. Docker Compose 설정 문법 검증
# ------------------------------------------------------------------------------
echo "[deploy] validating compose"
docker compose config >/dev/null

# ------------------------------------------------------------------------------
# 6. Nginx 템플릿 검증 함수 정의
# ------------------------------------------------------------------------------
validate_nginx_template() {
  echo "[deploy] validating rendered nginx template"
  # nginx 공식 entrypoint가 envsubst를 실행한 뒤 nginx -t를 수행한다.
  # 포트를 publish하지 않는 일회성 컨테이너라 현재 운영 중인 nginx에 영향이 없다.
  docker compose run --rm --no-deps nginx nginx -t
}

# ------------------------------------------------------------------------------
# 7. 대상이 'portal'인 경우: Portal 웹 앱만 단독 배포 후 종료
# ------------------------------------------------------------------------------
if [ "$target" = "portal" ]; then
  echo "[deploy] applying portal only"
  # Portal-only 배포는 React/Go 코드만 바뀌었을 때 Nginx/DB 등 인프라 서비스를
  # 불필요하게 재기동하지 않고 빠르게 단독 빌드 및 교체한다.
  docker compose up -d --build --no-deps portal

  echo "[deploy] portal status"
  docker compose ps portal

  echo "[deploy] complete"
  exit 0
fi

# ------------------------------------------------------------------------------
# 8. 대상이 'all'인 경우: 전체 인프라 스택 배포
# ------------------------------------------------------------------------------
# Dockerfile 빌드 대상이 아닌 외부 공식 이미지(nginx, postgres, redis 등)를 미리 pull
echo "[deploy] pulling images"
docker compose pull --ignore-buildable

# 배포 전 Nginx 템플릿 환경변수 치환 및 문법 사전 검증
validate_nginx_template

# 전체 서비스 백그라운드 빌드 및 실행 (모든 헬스체크가 통과할 때까지 최대 120초 대기)
echo "[deploy] applying stack"
docker compose up -d --build --wait --wait-timeout 120

# bind mount의 template만 바뀌면 일반 up은 nginx를 재생성하지 않는다.
# 후보 설정 검증을 통과한 뒤 nginx만 강제로 재생성해 envsubst 결과를 갱신한다.
echo "[deploy] recreating nginx for rendered configuration"
docker compose up -d --no-deps --force-recreate --wait --wait-timeout 120 nginx

# 배포된 컨테이너 상태 목록 출력
echo "[deploy] compose status"
docker compose ps

# ------------------------------------------------------------------------------
# 9. 데이터베이스 및 캐시 서비스 로컬 연결 상태 검증
# ------------------------------------------------------------------------------
echo "[deploy] local postgres check"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[deploy] local redis check"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[deploy] complete"
