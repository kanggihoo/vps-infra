---
type: Decision
title: 빌드 결과를 Shared Library로 Mattermost에 알린다
description: 모든 Jenkins job이 implicit Shared Library의 notifyMattermost()로 성공·실패를 SSAFY Mattermost 한 채널에 보낸다.
tags: [jenkins, mattermost, notification, shared-library]
timestamp: 2026-09-29T00:00:00+09:00
---

# 결정

모든 Jenkins job은 성공과 실패를 SSAFY Mattermost의 한 채널로 알린다. 알림 코드는 vps-infra 레포의
`jenkins/shared-lib/vars/notifyMattermost.groovy` 하나에 두고, JCasC가 `vps-shared`라는
**implicit global library**로 등록한다. 각 `Jenkinsfile`은 `@Library` 없이
`post { always { notifyMattermost() } }`만 쓴다.

```txt
post always
-> notifyMattermost()          (vps-shared, main 기준)
-> mattermost-webhook credential (JCasC, jenkins/.env의 MATTERMOST_WEBHOOK_URL)
-> Mattermost incoming webhook (attachments)
```

# 메시지 형식

- 제목: `배포 성공|실패|불안정|중단 · <job> #<번호>`, 누르면 빌드 페이지로 간다. 결과별 색 막대.
- 필드: 커밋(짧은 SHA, GitHub 링크), 브랜치, 소요 시간, job이 넘긴 추가 필드(vps-infra는 배포 대상).
- 실패 시 본문 순서: ① 실패 단계 ② 오류 메시지 ③ 실패한 테스트 최대 5개(JUnit) ④ 로그 마지막 30줄.
  오류 메시지는 실패한 스텝 노드에서 읽는다. `error()`의 메시지는 빌드가 끝난 뒤에야 콘솔에 찍혀
  알림 시점의 로그에는 없기 때문이다.
  로그는 ANSI 색상 코드, Jenkins console note, 타임스탬프, `[Pipeline]`·` > git `·credential 마스킹 안내
  줄을 지우고 3000자로 자른다.

실패 단계를 로그보다 먼저 두는 이유: 로그 끝부분에는 실패 뒤의 정리·롤백 출력이 남아 원인이
묻히는 경우가 많다.

# 이유

- **mattermost plugin을 쓰지 않는다.** `mattermostSend`는 제목·본문·색만 보내고 attachments
  필드 표를 만들 수 없다.
- **셸 + curl 대신 Groovy 라이브러리다.** JSON을 만들려면 이미지에 `jq`가 필요하고, 두 레포가 같은
  스크립트를 쓰려면 마운트가 하나 더 필요하다. 신뢰된 global library는 sandbox 밖에서 돌아
  빌드 로그, flow graph(실패 단계), JUnit 결과를 직접 읽는다.
- **webhook URL은 `jenkins/.env`에만 둔다.** vps-info job도 써야 하므로 모든 job이 쓰는 Jenkins
  credential이어야 한다. SOPS 사본은 두지 않는다. 잃어버리면 Mattermost에서 다시 만들면 된다.

# 결과

- 2026-09-29 로컬 Jenkins(새 이미지, 가짜 webhook 서버)로 성공, JUnit 테스트 실패, Checkout 실패 세 경우의
  메시지를 확인했다. 그때 `it.class`가 `ParametersAction`에서 null을 돌려 파라미터가 있는 job의 알림이 실패하는
  버그를 찾아 `getClass()`로 고쳤다.
- 라이브러리는 항상 main을 읽는다. 알림 코드가 깨지면 모든 job이 영향을 받으므로 push 전에
  컴파일을 확인한다. `includeInChangesets: false`로 라이브러리 커밋이 다른 job의 빌드를 일으키지 않게 한다.
- 알림 전송 실패는 빌드 결과를 바꾸지 않는다. credential이 비어 있으면(로컬 Jenkins) 건너뛴다.
- 라이브러리가 쓰는 `ansiColor`, `junit` plugin을 먼저 설치한 뒤에 그것을 쓰는 `Jenkinsfile`을 push한다.
  순서가 바뀌면 declarative 검증에서 빌드가 시작부터 실패한다.
- Jenkins 지표(prometheus plugin)는 이번 범위에서 뺐다. 모니터링 구축(`OBSERVABILITY.md` 설계) 때 다룬다.

# 관련 개념

- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [Jenkins 배포](/services/jenkins-deploy.md)
- [vps-info (Signal Archive)](/services/vps-info.md)
