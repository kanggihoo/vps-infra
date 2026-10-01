// Job 정의. JCasC가 기동 시 이 스크립트를 실행해 Job을 만든다.
// GUI에서 Job을 고쳐도 재기동 시 이 정의로 되돌아간다(ADR 0009).
//
// SCM URL은 환경변수로 받는다. 로컬은 로컬 경로, VPS는 GitHub URL이다.
// 이렇게 두면 로컬 Jenkins가 push하지 않은 커밋으로 파이프라인을 테스트할 수 있다.

def infraRepo  = System.getenv('INFRA_SCM_URL')  ?: '/repo'
// 로컬 경로를 SCM으로 쓸 때는 credential이 필요 없다.
def scmCredential = System.getenv('SCM_CREDENTIAL_ID') ?: ''

pipelineJob('vps-infra-pipeline') {
    description('vps-infra 공통 인프라 배포. 정의는 jenkins/casc/jobs.groovy에 있다.')

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
// multibranch로 main과 같은 레포 PR을 빌드한다. PR은 Jenkinsfile의 when 조건 때문에 Test만 돌고,
// 결과는 GitHub commit status로 보고되어 브랜치 보호의 필수 check가 된다.
// fork PR은 발견하지 않는다. 이 Jenkins는 docker.sock을 쓰므로 외부 코드를 실행하면 안 된다.
// GitHub를 직접 조회하므로 로컬 Jenkins에서는 push하지 않은 커밋을 시험할 수 없다(이전 단일 job과 다른 점).
multibranchPipelineJob('vps-info') {
    description('vps-info PR 검증과 main 배포. 정의는 vps-infra/jenkins/casc/jobs.groovy에 있다.')

    branchSources {
        github {
            id('vps-info-github')
            repoOwner('kanggihoo')
            repository('vps-info')
            scanCredentialsId('github-pat')
            traits {
                // 브랜치: 1 = PR이 없는 브랜치만 빌드(PR 중복 빌드 방지). PR: 1 = 대상 브랜치와 병합한 결과로 빌드.
                gitHubBranchDiscovery { strategyId(1) }
                gitHubPullRequestDiscovery { strategyId(1) }
            }
        }
    }

    // Jenkinsfile 경로는 기본값(레포 루트)이다. 다른 브랜치는 PR이 생기기 전까지 Jenkinsfile의 when으로 배포가 막힌다.

    orphanedItemStrategy {
        discardOldItems { numToKeep(20) }
    }
}
