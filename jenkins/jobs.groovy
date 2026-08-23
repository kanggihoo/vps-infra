// Job 정의. JCasC가 기동 시 이 스크립트를 실행해 Job을 만든다.
// GUI에서 Job을 고쳐도 재기동 시 이 정의로 되돌아간다(ADR 0009).
//
// SCM URL은 환경변수로 받는다. 로컬은 로컬 경로, VPS는 GitHub URL이다.
// 이렇게 두면 로컬 Jenkins가 push하지 않은 커밋으로 파이프라인을 테스트할 수 있다.

def infraRepo  = System.getenv('INFRA_SCM_URL')  ?: '/repo'
def quartzRepo = System.getenv('QUARTZ_SCM_URL') ?: ''
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

// Quartz는 별도 레포가 Dockerfile과 compose.yml을 소유한다(ADR 0007).
// SCM URL이 설정되지 않은 환경(로컬 기본)에서는 Job을 만들지 않는다.
//
// ⚠️ 단계 7(Quartz 이미지화)이 아직 구현되지 않았다. 이전 구조에서 Jenkins는
// 호스트 /opt/quartz-build, /opt/quartz-site를 마운트해 빌드 산출물을 놓았는데,
// 그 마운트는 이 변경에서 제거되었다(named volume + 이미지화로 대체 예정).
// 따라서 QUARTZ_SCM_URL을 설정하면 Job은 생성되지만 기존 방식의 빌드는
// 실패한다. 단계 7에서 해당 레포의 Jenkinsfile을 이미지 빌드 방식으로
// 바꾼 뒤에 설정한다.
if (quartzRepo) {
    pipelineJob('quartz-deploy') {
        description('''quartz-site-private 빌드와 배포. 정의는 jenkins/jobs.groovy에 있다.

주의: 단계 7(이미지화) 미구현 상태다. 호스트 /opt/quartz-* 마운트가 제거되어
이전 방식의 빌드는 실패한다.''')

        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url(quartzRepo)
                            if (scmCredential) {
                                credentials(scmCredential)
                            }
                        }
                        branch('*/main')
                    }
                }
                scriptPath('Jenkinsfile')
                lightweight(false)
            }
        }

        // 최상위 triggers 블록은 deprecated 경고를 남긴다.
        properties {
            pipelineTriggers {
                triggers {
                    githubPush()
                }
            }
        }
    }
}
