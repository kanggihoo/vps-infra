// 빌드 결과를 Mattermost incoming webhook으로 보낸다(ADR 0012).
// JCasC가 implicit 라이브러리로 등록하므로 Jenkinsfile은 @Library 없이 부른다.
//
//   post { always { notifyMattermost() } }
//   notifyMattermost(commit: env.DEPLOY_SHA, repoUrl: env.INFRA_SCM_URL, fields: ['배포 대상': 'all'])
//   notifyMattermost(kind: 'CI')   // 제목 앞말. 생략하면 '배포'
//   notifyMattermost(gitDir: env.APP_DIR)   // 커밋을 읽을 git 디렉터리. 생략하면 현재 workspace
//
// PR 번호·제목은 multibranch PR 빌드의 CHANGE_* 환경변수에서, main 빌드는 커밋 메시지
// (`Merge pull request #N` 또는 squash의 `제목 (#N)`)에서 읽는다.
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
            def sha = args.commit ?: env.GIT_COMMIT
            def git = gitInfo(sha, args.gitDir)
            def payload = buildPayload(currentBuild.rawBuild, [
                result  : currentBuild.currentResult,
                job     : env.JOB_NAME,
                number  : env.BUILD_NUMBER,
                url     : env.BUILD_URL,
                duration: currentBuild.durationString.replace(' and counting', ''),
                commit  : sha,
                repoUrl : args.repoUrl ?: env.GIT_URL,
                kind    : args.kind ?: '배포',
                // multibranch의 PR 빌드는 BRANCH_NAME이 PR-7이다. 단일 job은 GIT_BRANCH를 쓴다.
                branch  : env.BRANCH_NAME ?: (env.GIT_BRANCH ?: 'main').replaceFirst(/^origin\//, ''),
                fields  : args.fields ?: [:],
                // PR 빌드에만 있다. main 빌드는 아래 git 정보에서 PR 번호를 찾는다.
                changeId    : env.CHANGE_ID,
                changeTitle : env.CHANGE_TITLE,
                changeAuthor: env.CHANGE_AUTHOR,
                changeBranch: env.CHANGE_BRANCH,
                changeTarget: env.CHANGE_TARGET,
                changeUrl   : env.CHANGE_URL,
                git         : git,
                pr          : parsePr(git.subject ?: '', git.body ?: ''),
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

    def prNumber = b.changeId ?: b.pr.number
    def prTitle = b.changeTitle ?: b.pr.title
    def rm = b.repoUrl =~ /^https:\/\/github\.com\/(.+?)(\.git)?\/?$/
    def repo = rm.find() ? rm.group(1) : null
    def prUrl = b.changeUrl ?: (prNumber && repo ? "https://github.com/${repo}/pull/${prNumber}" : null)
    def prLink = prNumber ? (prUrl ? "[#${prNumber}](${prUrl})" : "#${prNumber}") : null

    def fields = []
    if (prLink) {
        fields << ['short': true, title: 'PR', value: prLink]
    }
    if (b.changeId) {
        fields << ['short': true, title: '작성자', value: b.changeAuthor ?: '-']
        fields << ['short': true, title: '브랜치 → 대상', value: "${b.changeBranch} → ${b.changeTarget}".toString()]
    } else if (prNumber) {
        fields << ['short': true, title: '병합자', value: b.git.author ?: '-']
    } else {
        fields << ['short': true, title: '브랜치', value: b.branch]
    }
    fields << ['short': true, title: '커밋', value: commitLink(b.commit, b.repoUrl)]
    fields << ['short': true, title: '소요 시간', value: b.duration]
    // Jenkinsfile이 넘기던 PR 필드는 위에서 이미 만들었으므로 중복을 뺀다.
    b.fields.each { k, v ->
        if (!(prLink && k == 'PR')) {
            fields << ['short': true, title: k as String, value: (v ?: '-') as String]
        }
    }

    // 요약 한 줄: PR 번호와 제목. PR이 아니면 커밋 제목이다.
    def subject = prTitle ?: b.git.subject
    def summary = [prNumber ? "PR #${prNumber}" : null, subject ? "「${subject}」" : null].findAll { it }.join(' ')
    if (b.kind == 'CI' && summary) {
        summary += b.result == 'SUCCESS' ? ' 검증을 통과했습니다. 리뷰 가능합니다.' : " 검증 결과: ${label}"
    }
    def text = [summary, b.result == 'SUCCESS' ? '' : failureText(run)].findAll { it }.join('\n\n')

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

// 커밋 제목·작성자·본문. sha가 없거나 git 호출이 실패하면 빈 값이라 알림은 PR 정보 없이 나간다.
Map gitInfo(String sha, String gitDir = null) {
    if (!(sha ==~ /[0-9a-f]{7,40}/) || (gitDir && !(gitDir ==~ /[\w.\/-]+/))) {
        return [:]
    }
    try {
        def cd = gitDir ? "cd '${gitDir}' && " : ''
        def out = sh(script: "${cd}git log -1 --format=%s%x1f%an%x1f%b ${sha}", returnStdout: true).trim()
        def p = out.split('\u001f', -1)
        return [subject: p[0], author: p.length > 1 ? p[1] : '', body: p.length > 2 ? p[2] : '']
    } catch (e) {
        echo "[notify] 커밋 정보를 읽지 못했다: ${e}"
        return [:]
    }
}

// 병합 커밋 `Merge pull request #3 from a/b`(제목은 본문 첫 줄)와 squash `제목 (#3)`를 알아본다.
@NonCPS
Map parsePr(String subject, String body) {
    def m = subject =~ /^Merge pull request #(\d+) from \S+/
    if (m.find()) {
        return [number: m.group(1), title: body.readLines().find { it.trim() }?.trim() ?: subject]
    }
    m = subject =~ /^(.*) \(#(\d+)\)$/
    m.find() ? [number: m.group(2), title: m.group(1)] : [:]
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
