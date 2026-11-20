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
        choiceParam('DEPLOY_TARGET', ['auto', 'all', 'portal', 'observability'],
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
// multibranch로 main만 빌드해 배포한다. PR 검증은 vps-info의 GitHub Actions가 한다(ADR 0018).
// PR을 발견하지 않으므로 외부 코드가 이 Jenkins(docker.sock)에서 돌 일도 없다.
// single pipelineJob으로 되돌리지 않는 이유: BRANCH_NAME이 비어 Jenkinsfile의 when { branch 'main' }이
// 항상 거짓이 되고, 배포 stage를 건너뛴 채 빌드가 성공으로 표시된다(ADR 0014).
multibranchPipelineJob('vps-info') {
    description('vps-info main 배포. 정의는 vps-infra/jenkins/casc/jobs.groovy에 있다.')

    branchSources {
        github {
            id('vps-info-github')
            repoOwner('kanggihoo')
            repository('vps-info')
            scanCredentialsId('github-pat')
            // main만 발견한다. 기본값('*')이면 PR이 없는 작업 브랜치마다 Test 빌드가 생긴다.
            includes('main')
            // 이 Job DSL 버전의 github 소스는 traits 대신 아래 옵션을 직접 받는다. PR은 빌드하지 않는다.
            buildOriginBranch(true)
            buildOriginBranchWithPR(false)
            buildOriginPRMerge(false)
            buildOriginPRHead(false)
            buildForkPRMerge(false)
            buildForkPRHead(false)
        }
    }

    // Jenkinsfile 경로는 기본값(레포 루트)이다.

    // GitHub webhook은 자동 재시도가 없어 연결이 한 번 실패하면 push 이벤트가 유실된다.
    // 15분마다 스캔해 놓친 main push를 보완한다(ADR 0015). webhook은 즉시 반응용으로 그대로 둔다.
    triggers {
        periodicFolderTrigger { interval('15m') }
    }

    orphanedItemStrategy {
        discardOldItems { numToKeep(20) }
    }
}
