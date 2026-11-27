# 기여 가이드

이 repository는 Hostinger VPS 1대의 공통 인프라를 관리한다. main에 들어간 commit은 GitHub Actions가 곧바로 VPS에 배포하므로, 모든 변경은 PR을 거친다.
배포 흐름의 상세는 [배포 문서](okf/services/deploy.md)에 있고, 이 문서는 변경을 main에 넣기까지의 규칙만 다룬다.

## 작업 시작

작업 전에 `okf/index.md`를 읽고 관련 개념 문서를 따라간다.

branch 이름은 `type/kebab-case`로 짓는다. 예를 들어 `ci/split-workflows-by-trigger`, `chore/remove-jenkins`처럼 쓴다.
type은 아래 PR 제목 규칙과 같은 목록에서 고른다.

로컬 secret 검사를 켜려면 Gitleaks 8.30.1과 Lefthook을 설치한 뒤 레포 루트에서 `lefthook install`을 실행한다.
그러면 commit마다 `scripts/scan-secrets.sh staged`가 staged 변경을 검사한다.

## 새 셸 스크립트

Windows에서 만든 `.sh` 파일은 git에 실행 권한 없이(`100644`) 들어간다. Windows의 git은 clone할 때 `.git/config`에 `core.fileMode=false`를 넣어 파일 권한을 무시하기 때문이다.
그대로 push하면 Linux runner와 VPS에서 `./scripts/xxx.sh`가 `Permission denied`로 실패한다. Windows에서 새 스크립트를 추가하면 commit 전에 실행 권한을 준다.
macOS에서는 `chmod +x`한 권한이 그대로 commit되므로 `git update-index` 단계가 필요 없다. 어느 OS에서든 마지막 확인 명령으로 `100755`인지 본다.

```sh
git add scripts/new-script.sh
git update-index --chmod=+x scripts/new-script.sh
git ls-files -s scripts/new-script.sh   # 100755로 나와야 한다
```

줄바꿈은 `.gitattributes`가 `*.sh`를 LF로 고정하므로 따로 신경 쓰지 않아도 된다.

## 로컬 검증

바꾼 영역에 맞춰 CI와 같은 검사를 로컬에서 먼저 돌린다. CI 정의는 `.github/workflows/ci.yml`에 있다.

| 바꾼 영역 | 명령 |
|-----------|------|
| nginx 템플릿 | `./scripts/test-nginx-templates.sh` |
| compose 파일 | `cp .env.example .env && docker compose config >/dev/null` |
| 배포 대상 선택 로직 | `./scripts/test-select-target.sh` |
| `deploy.sh`의 `.env` 가드 | `./scripts/test-deploy-guards.sh` |
| 라우팅·Tinyauth SSO (스택 기동 후, CI 밖) | `./scripts/test-routing.sh` |
| SOPS 파일 | `./scripts/check-sops.sh` |

## PR 제목

squash merge는 PR 제목을 main의 commit 제목으로, PR 본문을 commit 본문으로 쓴다. 그래서 PR 제목은 commit 제목 규칙을 따른다.

형식은 `type: 한국어로 ~한다`이다. 예를 들어 `ci: vps-infra 배포를 GitHub Actions로 옮긴다`처럼 쓴다.

| type | 쓰는 경우 |
|------|-----------|
| `feat` | 새 기능이나 라우팅 추가 |
| `fix` | 버그 수정 |
| `refactor` | 동작을 바꾸지 않는 구조 변경 |
| `docs` | 문서와 OKF만 바꾸는 변경 |
| `ci` | GitHub Actions workflow와 배포 경로 변경 |
| `chore` | 정리, 의존성, 그 밖의 유지보수 |
| `revert` | 이전 변경 되돌리기 |

PR 본문은 `.github/PULL_REQUEST_TEMPLATE.md`의 섹션을 채운다. 본문도 commit 메시지로 남으므로 기록할 가치가 있는 내용만 쓴다.

## merge 규칙

main에는 ruleset이 걸려 있다. 정의는 `.github/rulesets/main.json`에 있다.

- main에 직접 push할 수 없다. 모든 변경은 PR로 들어온다.
- PR은 `ci / gate` check를 통과해야 merge할 수 있다.
- PR branch는 최신 main을 포함해야 한다. 다른 PR이 먼저 merge되면 merge 버튼이 막힌다. 이때 PR 화면의 "Update branch"를 누르면 main이 PR branch에 합쳐지고 CI가 다시 돈다. 새 CI가 통과하면 다시 merge할 수 있다.
- squash merge만 허용한다. merge 후 head branch는 자동으로 지워진다.
- conflict가 있으면 GitHub가 merge와 Update branch를 막는다. 로컬에서 main을 합쳐 conflict를 해결한 뒤 push한다.
- repository admin은 PR을 통해서만 규칙을 우회할 수 있다. 직접 push는 admin도 막힌다.

GitHub UI에서 설정을 바꾸면 파일과 어긋난다. 설정을 바꿀 때는 `.github/rulesets/main.json`이나 `scripts/apply-github-settings.sh`를 고친 뒤 스크립트를 실행한다.

## merge 이후

main에 들어간 commit은 `Infra deploy` workflow가 CI를 다시 돌린 뒤 Portal 이미지를 게시하고 VPS에 배포한다.
같은 SHA를 다시 적용하려면 `Infra redeploy` workflow를 수동 실행한다. 절차는 [배포 문서](okf/services/deploy.md)에 있다.

`scripts/ci-deploy.sh`를 바꾼 변경은 그다음 배포부터 적용된다. VPS에 이미 있는 스크립트가 먼저 실행돼 새 commit을 checkout하기 때문이다.

## OKF

운영 지식이 바뀌면 같은 PR에서 `okf/`를 갱신한다. workflow 파일 이름, 배포 흐름, 설정값처럼 다른 문서가 가리키는 사실이 특히 그렇다.
OKF를 고친 뒤에는 strict validation을 실행한다.
