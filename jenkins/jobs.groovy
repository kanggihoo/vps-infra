// Job 정의. JCasC가 기동 시 이 스크립트를 실행해 Job을 만든다.
// GUI에서 Job을 고쳐도 재기동 시 이 정의로 되돌아간다(ADR 0009).
//
// SCM URL은 환경변수로 받는다. 로컬은 로컬 경로, VPS는 GitHub URL이다.
// 이렇게 두면 로컬 Jenkins가 push하지 않은 커밋으로 파이프라인을 테스트할 수 있다.

def infraRepo  = System.getenv('INFRA_SCM_URL')  ?: '/repo'
// 로컬 경로를 SCM으로 쓸 때는 credential이 필요 없다.
def scmCredential = System.getenv('SCM_CREDENTIAL_ID') ?: ''

pipelineJob('vps-infra-pipeline') {
    description('vps-infra 공통 인프라 배포. 정의는 jenkins/jobs.groovy에 있다.')

    parameters {
        choiceParam('DEPLOY_TARGET', ['auto', 'all', 'portal'],
            '배포 대상. auto는 변경 파일로 판정하고, 판정 불가 시 실패한다.')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(infraRepo)
                        if (scmCredential) {
                            credentials(scmCredential)
                        }
                    }
                    branch('*/main')
                }
            }
            scriptPath('Jenkinsfile')
            // false여야 트리거 판정에 필요한 정보를 얻는다.
            // lightweight checkout은 Jenkinsfile만 가져와 diff 판정이 불가능해진다.
            lightweight(false)
        }
    }

    // pipelineJob에서는 properties 안에 두는 것이 현재 권장 표기다.
    // 최상위 triggers 블록은 deprecated 경고를 남긴다.
    properties {
        pipelineTriggers {
            triggers {
                githubPush()
            }
        }
    }
}

// vps-info는 자기 레포가 Dockerfile, compose.yml, Jenkinsfile을 소유한다(ADR 0007).
// public 레포라 checkout에 credential이 필요 없다. 로컬 시험은 환경변수로 로컬 경로를 준다.
pipelineJob('vps-info') {
    description('vps-info 빌드와 배포. 정의는 vps-infra/jenkins/jobs.groovy에 있다.')

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(System.getenv('VPS_INFO_SCM_URL') ?: 'https://github.com/kanggihoo/vps-info.git')
                    }
                    branch('*/main')
                }
            }
            scriptPath('Jenkinsfile')
            lightweight(false)
        }
    }

    properties {
        pipelineTriggers {
            triggers {
                githubPush()
            }
        }
    }
}
