// 빌드 결과를 Mattermost incoming webhook으로 보낸다(ADR 0012).
// JCasC가 implicit 라이브러리로 등록하므로 Jenkinsfile은 @Library 없이 부른다.
//
//   post { always { notifyMattermost() } }
//   notifyMattermost(commit: env.DEPLOY_SHA, repoUrl: env.INFRA_SCM_URL, fields: ['배포 대상': 'all'])
//   notifyMattermost(kind: 'CI')   // 제목 앞말. 생략하면 '배포'
//
// 신뢰된 global library라 sandbox 밖에서 돈다. 그래서 빌드 로그, flow graph, JUnit 결과를
// 직접 읽을 수 있다. 알림 실패는 빌드 결과를 바꾸지 않는다.

import groovy.json.JsonOutput

def call(Map args = [:]) {
    try {
        withCredentials([string(credentialsId: 'mattermost-webhook', variable: 'MATTERMOST_HOOK')]) {
            if (!env.MATTERMOST_HOOK?.trim()) {
                echo '[notify] mattermost-webhook이 비어 있어 알림을 건너뛴다'
                return
            }
            def payload = buildPayload(currentBuild.rawBuild, [
                result  : currentBuild.currentResult,
                job     : env.JOB_NAME,
                number  : env.BUILD_NUMBER,
                url     : env.BUILD_URL,
                duration: currentBuild.durationString.replace(' and counting', ''),
                commit  : args.commit ?: env.GIT_COMMIT,
                repoUrl : args.repoUrl ?: env.GIT_URL,
                kind    : args.kind ?: '배포',
                // multibranch의 PR 빌드는 BRANCH_NAME이 PR-7이다. 단일 job은 GIT_BRANCH를 쓴다.
                branch  : env.BRANCH_NAME ?: (env.GIT_BRANCH ?: 'main').replaceFirst(/^origin\//, ''),
                fields  : args.fields ?: [:],
            ])
            int status = sendWebhook(env.MATTERMOST_HOOK, payload)
            echo "[notify] mattermost ${status}"
        }
    } catch (e) {
        echo "[notify] 알림 전송 실패(빌드 결과에는 영향 없음): ${e}"
    }
}

@NonCPS
String buildPayload(run, Map b) {
    def styles = [
        SUCCESS : ['성공', '#2eb886'],
        FAILURE : ['실패', '#d33f3f'],
        UNSTABLE: ['불안정', '#e8a33d'],
        ABORTED : ['중단', '#8b8b8b'],
    ]
    def (label, color) = styles[b.result] ?: [b.result, '#8b8b8b']

    def fields = [
        ['short': true, title: '커밋', value: commitLink(b.commit, b.repoUrl)],
        ['short': true, title: '브랜치', value: b.branch],
        ['short': true, title: '소요 시간', value: b.duration],
    ]
    b.fields.each { k, v -> fields << ['short': true, title: k as String, value: (v ?: '-') as String] }

    def text = b.result == 'SUCCESS' ? '' : failureText(run)

    JsonOutput.toJson([
        username   : 'Jenkins',
        attachments: [[
            color     : color,
            title     : "${b.kind} ${label} · ${b.job} #${b.number}",
            title_link: b.url,
            text      : text,
            fields    : fields,
        ]],
    ])
}

@NonCPS
String commitLink(String sha, String repoUrl) {
    if (!sha) {
        return '-'
    }
    def shortSha = "`${sha.take(7)}`"
    def m = repoUrl =~ /^https:\/\/github\.com\/(.+?)(\.git)?\/?$/
    m.find() ? "[${shortSha}](https://github.com/${m.group(1)}/commit/${sha})" : shortSha
}

// 실패 단계 → 실패한 테스트 → 로그 끝부분 순서다. 로그 끝만으로는 원인이
// 뒤따른 정리 출력에 묻히는 경우가 많아 단계 이름을 먼저 둔다.
@NonCPS
String failureText(run) {
    def parts = []
    def (stage, error) = failedStep(run)
    if (stage) {
        parts << "**실패 단계**: ${stage}"
    }
    // error()의 메시지는 빌드가 끝난 뒤에야 콘솔에 찍혀 로그 끝부분에 없다. 실패 노드에서 직접 읽는다.
    if (error) {
        parts << "**오류**: ${error.take(300)}"
    }
    def tests = failedTests(run)
    if (tests) {
        parts << "**실패한 테스트**\n" + tests.collect { "- ${it}" }.join('\n')
    }
    def log = logTail(run)
    if (log) {
        parts << "```\n${log}\n```"
    }
    parts.join('\n\n')
}

@NonCPS
List failedStep(run) {
    def execution = run.execution
    if (execution == null) {
        return [null, null]
    }
    for (node in new org.jenkinsci.plugins.workflow.graph.FlowGraphWalker(execution)) {
        // 실패를 일으킨 스텝(sh, error 등)만 본다. 블록 끝 노드도 에러를 전파받아 갖고 있어
        // 그것까지 보면 바깥 블록의 이름이 잡힌다.
        if (!(node instanceof org.jenkinsci.plugins.workflow.cps.nodes.StepAtomNode) || node.getError() == null) {
            continue
        }
        def stage = node.enclosingBlocks.find {
            it.getAction(org.jenkinsci.plugins.workflow.actions.LabelAction) != null &&
                it.getAction(org.jenkinsci.plugins.workflow.actions.ThreadNameAction) == null
        }
        def message = node.getError().error?.message
        def label = stage?.getAction(org.jenkinsci.plugins.workflow.actions.LabelAction)?.displayName
        return [label, message]
    }
    [null, null]
}

// junit 플러그인이 없어도 라이브러리가 로드되도록 클래스를 이름으로 찾는다.
// it.class는 쓰지 않는다. ParametersAction처럼 동적 property를 가진 action은 null을 돌려준다.
@NonCPS
List failedTests(run) {
    def action = run.allActions.find { it.getClass().name == 'hudson.tasks.junit.TestResultAction' }
    if (action == null) {
        return []
    }
    def failed = action.failedTests
    def lines = failed.take(5).collect { c ->
        def error = (c.errorDetails ?: '').readLines().find { it.trim() } ?: ''
        "${c.className} > ${c.displayName}" + (error ? " — ${error.trim().take(200)}" : '')
    }
    if (failed.size() > 5) {
        lines << "외 ${failed.size() - 5}개"
    }
    lines
}

// 색상 코드와 Jenkins 내부 표기를 지우고, 원인과 무관한 줄을 빼고 30줄/3000자로 자른다.
// 빼는 줄: 파이프라인 구조([Pipeline]), git 명령 에코(라이브러리 checkout 포함), credential 마스킹 안내.
@NonCPS
String logTail(run) {
    def lines = run.getLog(300).collect { line ->
        hudson.console.ConsoleNote.removeNotes(line)
            .replaceAll(/\u001B\[[0-9;]*[A-Za-z]/, '')
            .replaceFirst(/^\[\d{4}-\d\d-\d\dT[\d:.]+Z\] /, '')
    }.findAll { line ->
        !(line.startsWith('[Pipeline]') || line.startsWith(' > git ') || line.startsWith('Masking supported pattern'))
    }
    def text = lines.takeRight(30).join('\n')
    text.length() > 3000 ? text.substring(text.length() - 3000) : text
}

@NonCPS
int sendWebhook(String url, String payload) {
    def conn = new URL(url).openConnection()
    conn.requestMethod = 'POST'
    conn.doOutput = true
    conn.connectTimeout = 10000
    conn.readTimeout = 10000
    conn.setRequestProperty('Content-Type', 'application/json; charset=utf-8')
    conn.outputStream.withWriter('UTF-8') { it << payload }
    conn.responseCode
}
