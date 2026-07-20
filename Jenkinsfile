pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 15, unit: 'MINUTES')
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                dir('/opt/vps-infra') {
                    checkout scm
                }
            }
        }

        stage('Select target') {
            steps {
                script {
                    dir('/opt/vps-infra') {
                        def changed = sh(
                            script: 'git diff --name-only HEAD^ HEAD 2>/dev/null || git diff-tree --no-commit-id --name-only -r HEAD',
                            returnStdout: true
                        ).trim()
                        def files = changed ? changed.readLines() : []
                        env.DEPLOY_TARGET = files && files.every { it.startsWith('portal/') } ? 'portal' : 'all'
                        echo "Deploy target: ${env.DEPLOY_TARGET}"
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                dir('/opt/vps-infra') {
                    sh 'chmod +x scripts/deploy.sh scripts/healthcheck.sh'
                    sh './scripts/deploy.sh "$DEPLOY_TARGET"'
                }
            }
        }

        stage('Health check') {
            steps {
                dir('/opt/vps-infra') {
                    sh './scripts/healthcheck.sh'
                }
            }
        }
    }
}
