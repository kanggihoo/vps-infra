// 오케스트레이션만 담는다. 판정 로직은 scripts/select-target.sh에 있다.
// 여기에 Groovy 로직을 다시 넣으면 로컬에서 실행할 수 없게 된다.
pipeline {
    // 사용 가능한 어떤 Jenkins 에이전트(노드)에서든 파이프라인 실행
    agent any

    options {
        // Jenkins 기본 자동 체크아웃 비활성화 (아래 Checkout 스테이지에서 $APP_DIR로 직접 제어)
        skipDefaultCheckout(true)
        // 이전 빌드가 실행 중일 때 새 Git push가 오면 동시 실행하지 않고 큐에 대기
        disableConcurrentBuilds()
        // 파이프라인이 15분 이상 지연되면 무한 루프 방지를 위해 자동 중단(타임아웃)
        timeout(time: 15, unit: 'MINUTES')
        // 빌드 콘솔 출력 로그의 각 줄마다 실행 시각(타임스탬프) 기록
        timestamps()
        // 콘솔의 ANSI 색상 코드를 색으로 보여준다(ansicolor plugin)
        ansiColor('xterm')
    }

    parameters {
        // 수동 빌드 실행 시 배포 범위를 선택할 수 있는 파라미터 드롭다운 제공
        // auto = 스크립트가 판정한다. 판정 불가면 빌드가 멈춘다.
        // portal/all = 판정을 건너뛰고 그 대상으로 배포한다(수동 빌드, 재배포).
        choice(
            name: 'DEPLOY_TARGET',
            choices: ['auto', 'all', 'portal'],
            description: '배포 대상. auto는 변경 파일로 판정하고, 판정 불가 시 실패한다.'
        )
    }

    // APP_DIR은 Jenkins 컨테이너의 환경변수로 주입된다(jenkins/compose.yml).
    // 호스트와 컨테이너에 같은 경로로 마운트되어 있어야 한다 — docker.sock으로
    // 실행하는 docker run의 -v 경로는 호스트 기준이기 때문이다.
    // environment 블록에서 자기 자신을 참조하면(env.APP_DIR) 값을 읽지 못하므로
    // 여기서 재정의하지 않고 컨테이너 값을 그대로 쓴다.
    //
    // dir(APP_DIR)을 쓰지 않는 이유: dir() 스텝은 작업 디렉터리 옆에
    // "<dir>@tmp"를 만든다. APP_DIR이 호스트 경로와 같아야 하는 제약 때문에
    // 그 부모 디렉터리가 Jenkins 소유가 아닐 수 있고, 그러면
    // AccessDeniedException으로 실패한다. 대신 sh 안에서 cd 한다.

    stages {
        // [1단계] 배포 경로의 소스 코드를 최신 Git 커밋으로 동기화
        stage('Checkout') {
            steps {
                script {
                    // 설정되지 않았으면 즉시 멈춘다. 기본값으로 엉뚱한 경로에
                    // 배포하는 것보다 실패가 낫다.
                    if (!env.APP_DIR) {
                        error 'APP_DIR is not set (jenkins/compose.yml에서 주입한다)'
                    }
                }
                // 배포 경로를 최신 커밋으로 맞춘다.
                //
                // reset --hard를 쓰지 않는 이유: 로컬에서는 APP_DIR이 개발자가
                // 편집 중인 레포 자체일 수 있고, 그러면 커밋하지 않은 작업을
                // 파괴한다. ff-only pull은 로컬 변경이 있으면 실패해서 멈춘다.
                //
                // UPDATE_APP_DIR=false면 갱신을 건너뛴다. 이미 원하는 커밋을
                // 체크아웃해 둔 상태로 파이프라인만 시험할 때 쓴다.
                sh '''
                    set -eu
                    cd "$APP_DIR"
                    if [ "${UPDATE_APP_DIR:-true}" = "true" ]; then
                        git pull --ff-only
                    else
                        echo "[checkout] UPDATE_APP_DIR=false, 갱신 생략"
                    fi
                    git log --oneline -1
                '''

                // 이 실행이 배포할 소스를 여기서 한 번 고정한다.
                // 이후 GitHub에 새 push가 와도 현재 checkout의 SHA는 바뀌지 않는다.
                // 대입문은 declarative steps에 바로 둘 수 없어 script 블록이 필요하다.
                script {
                    env.DEPLOY_SHA = sh(
                        script: 'cd "$APP_DIR" && git rev-parse HEAD',
                        returnStdout: true
                    ).trim()
                }
                echo "Deploy SHA: ${env.DEPLOY_SHA}"
            }
        }

        // [2단계] Git diff를 분석하여 배포 대상 결정 (portal만 배포 vs all 전체 배포)
        stage('Select target') {
            steps {
                script {
                    if (params.DEPLOY_TARGET && params.DEPLOY_TARGET != 'auto') {
                        env.RESOLVED_TARGET = params.DEPLOY_TARGET
                        echo "Deploy target (override): ${env.RESOLVED_TARGET}"
                    } else {
                        // 마지막 성공 배포부터 이번 고정 SHA까지의 누적 변경을 본다.
                        // 상태가 없거나 history가 끊기면 일부 변경을 누락하지 않도록 all을 고른다.
                        env.RESOLVED_TARGET = sh(
                            script: '''
                                set -eu
                                cd "$APP_DIR"
                                state_file=.deploy-state/last-successful-sha

                                if [ -f "$state_file" ]; then
                                    previous_sha="$(cat "$state_file")"
                                    if printf '%s' "$previous_sha" | grep -Eq '^[0-9a-f]{40}$' && \
                                       git cat-file -e "${previous_sha}^{commit}" 2>/dev/null && \
                                       git merge-base --is-ancestor "$previous_sha" "$DEPLOY_SHA"; then
                                        ./scripts/select-target.sh "$previous_sha" "$DEPLOY_SHA"
                                        exit 0
                                    fi
                                    echo "[select-target] saved deployment SHA is not an ancestor; deploying all" >&2
                                else
                                    echo "[select-target] no successful deployment SHA; deploying all" >&2
                                fi
                                echo all
                            ''',
                            returnStdout: true
                        ).trim()
                        echo "Deploy target (auto): ${env.RESOLVED_TARGET}"
                    }
                }
            }
        }

        // 커밋된 SOPS 파일로 .env와 secret 파일을 다시 만든다. 운영 값의 원본은 레포다.
        // VPS에서 .env를 직접 고치면 다음 배포에서 덮어써진다.
        // SECRETS_ENV는 로컬 Jenkins에서 local로 바꾼다(jenkins/compose.yml).
        stage('Decrypt secrets') {
            steps {
                withCredentials([file(credentialsId: 'sops-age-key', variable: 'SOPS_AGE_KEY_FILE')]) {
                    sh 'cd "$APP_DIR" && ENV_NAME="${SECRETS_ENV:-prod}" ./scripts/secrets.sh decrypt'
                }
            }
        }

        // [3단계] 판정된 대상에 따라 Docker Compose 빌드 및 컨테이너 재배포
        stage('Deploy') {
            steps {
                // 실행 권한은 git에 755로 커밋한다. chmod는 checkout에 로컬 변경을 남겨 다음 git pull을 막는다.
                sh 'cd "$APP_DIR" && ./scripts/deploy.sh "$RESOLVED_TARGET"'
            }
        }

        // [4단계] Nginx 및 주요 서비스가 정상 작동(200 OK)하는지 최종 헬스체크 검증
        stage('Health check') {
            steps {
                // Jenkins 안에서는 공개 DNS를 거치지 않고 nginx 컨테이너로
                // 직접 붙는다. VPS의 hairpin 라우팅을 피하고, 로컬에서는
                // health.localhost가 컨테이너 안에서 해석되지 않는 문제를 피한다.
                sh 'cd "$APP_DIR" && HEALTHCHECK_CONNECT_HOST=vps-nginx ./scripts/healthcheck.sh'
            }
        }

        stage('Record successful deployment') {
            steps {
                sh '''
                    set -eu
                    cd "$APP_DIR"
                    # runtime state라 Git에 넣지 않는다. 임시 파일을 rename해 중간에
                    # Jenkins가 죽어도 깨진 SHA 파일을 남기지 않는다.
                    state_dir=.deploy-state
                    state_file="$state_dir/last-successful-sha"
                    mkdir -p "$state_dir"
                    umask 077
                    temporary_file="$state_file.tmp.$$"
                    printf '%s\n' "$DEPLOY_SHA" > "$temporary_file"
                    mv "$temporary_file" "$state_file"
                '''
            }
        }

        // jenkins/casc/는 Jenkins에 마운트되어 있어 Checkout의 git pull로 이미 최신이다.
        // JCasC는 기동과 reload 때만 파일을 읽으므로 여기서 reload한다(ADR 0009).
        // 같은 설정을 다시 적용해도 결과가 같아 변경 여부를 판정하지 않는다.
        // 설정 오류가 있으면 이 단계가 실패한다.
        stage('Reload Jenkins config') {
            steps {
                // set +x: sh 스텝의 xtrace가 토큰을 콘솔 로그에 남기지 않게 한다.
                sh '''
                    set +x
                    # 설정 오류는 HTTP 오류가 아니라 {"status":"error"} 본문으로 올 수 있다.
                    response="$(curl -fsS -X POST \
                        "http://localhost:8080/reload-configuration-as-code/?casc-reload-token=$CASC_RELOAD_TOKEN")"
                    if printf '%s' "$response" | grep -q '"status" *: *"error"'; then
                        echo "[reload] failed: $response" >&2
                        exit 1
                    fi
                    echo "[reload] JCasC reloaded"
                '''
            }
        }
    }

    // 성공·실패를 Mattermost로 알린다. notifyMattermost는 JCasC가 implicit으로 등록한
    // vps-shared 라이브러리에 있다(jenkins/shared-lib, ADR 0012).
    post {
        always {
            notifyMattermost(
                commit: env.DEPLOY_SHA,
                repoUrl: env.INFRA_SCM_URL,
                fields: ['배포 대상': env.RESOLVED_TARGET]
            )
        }
    }
}
