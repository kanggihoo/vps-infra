pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
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
                    def changed = sh(
                        script: 'git -C /opt/vps-infra diff --name-only HEAD^ HEAD 2>/dev/null || git -C /opt/vps-infra diff-tree --no-commit-id --name-only -r HEAD',
                        returnStdout: true
                    ).trim()
                    def files = changed ? changed.readLines() : []
                    env.DEPLOY_TARGET = files && files.every { it.startsWith('portal/') } ? 'portal' : 'all'
                    echo "Deploy target: ${env.DEPLOY_TARGET}"
                }
            }
        }

        stage('Deploy') {
            steps {
                sh 'chmod +x /opt/vps-infra/scripts/deploy.sh /opt/vps-infra/scripts/healthcheck.sh'
                sh '/opt/vps-infra/scripts/deploy.sh "$DEPLOY_TARGET"'
            }
        }

        stage('Health check') {
            steps {
                sh '/opt/vps-infra/scripts/healthcheck.sh'
            }
        }
    }
}
