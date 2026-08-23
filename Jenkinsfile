// 오케스트레이션만 담는다. 판정 로직은 scripts/select-target.sh에 있다.
// 여기에 Groovy 로직을 다시 넣으면 로컬에서 실행할 수 없게 된다.
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 15, unit: 'MINUTES')
        timestamps()
    }

    parameters {
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
            }
        }

        stage('Select target') {
            steps {
                script {
                    if (params.DEPLOY_TARGET && params.DEPLOY_TARGET != 'auto') {
                        env.RESOLVED_TARGET = params.DEPLOY_TARGET
                        echo "Deploy target (override): ${env.RESOLVED_TARGET}"
                    } else {
                        // 판정은 스크립트가 한다. 판정 불가면 exit 1로 빌드가 멈춘다.
                        // 의도적으로 배포하려면 DEPLOY_TARGET 파라미터로 override한다.
                        env.RESOLVED_TARGET = sh(
                            script: 'cd "$APP_DIR" && ./scripts/select-target.sh HEAD~1 HEAD',
                            returnStdout: true
                        ).trim()
                        echo "Deploy target (auto): ${env.RESOLVED_TARGET}"
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                sh 'cd "$APP_DIR" && chmod +x scripts/*.sh && ./scripts/deploy.sh "$RESOLVED_TARGET"'
            }
        }

        stage('Health check') {
            steps {
                // Jenkins 안에서는 공개 DNS를 거치지 않고 nginx 컨테이너로
                // 직접 붙는다. VPS의 hairpin 라우팅을 피하고, 로컬에서는
                // health.localhost가 컨테이너 안에서 해석되지 않는 문제를 피한다.
                sh 'cd "$APP_DIR" && HEALTHCHECK_CONNECT_HOST=vps-nginx ./scripts/healthcheck.sh'
            }
        }
    }
}
