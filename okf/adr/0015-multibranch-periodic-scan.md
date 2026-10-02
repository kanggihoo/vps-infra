---
type: Decision
title: vps-info multibranch가 15분마다 스캔해 유실된 webhook을 보완한다
description: GitHub webhook은 자동 재시도가 없어 PR 생성 이벤트가 유실될 수 있으므로, multibranch job에 15분 주기 스캔을 두어 놓친 PR을 찾는다.
tags: [jenkins, multibranch, webhook, github, reliability]
timestamp: 2026-10-03T00:00:00+09:00
---

# 결정

`vps-info` multibranch job에 `periodicFolderTrigger`를 15분 간격으로 둔다([ADR 0014](/adr/0014-multibranch-pr-ci.md)).
webhook은 즉시 반응용으로 그대로 두고, 스캔은 놓친 이벤트를 늦게라도 잡는 안전망이다.

# 배경

2026-10-03 PR #3의 `pull_request.opened` webhook이 연결 단계에서 실패해 Jenkins에 PR이 생기지 않았다.
GitHub는 실패한 webhook을 자동 재시도하지 않으므로 이벤트 기반만으로는 이런 누락을 스스로 복구하지 못한다.
조사 과정과 원인 추정은 [트러블슈팅](/troubleshooting/webhook-pr-event-lost.md)에 있다.

# 이유

- webhook 전송은 보장되지 않으므로 이벤트 기반만으로는 PR이 조용히 누락된다. 누락되면 필수 check가
  `Expected`로 남아 병합이 막히지만, 원인이 보이지 않는다.
- 스캔은 GitHub API 호출이 적다. 레포 하나의 브랜치·PR 목록 조회라 PAT의 시간당 한도에 부담이 없다.
- 15분은 놓친 PR이 최대 15분 안에 잡히는 선에서 정했다. 더 줄여도 되지만 webhook이 평소 즉시 처리하므로
  보완용으로는 충분하다.

# 결과

- webhook이 실패해도 최대 약 15분 안에 PR 빌드가 생긴다.
- 변경이 없을 때의 스캔은 빌드를 만들지 않는다.
- 이 설정은 `jenkins/casc/jobs.groovy`에 있고, JCasC reload로 반영된다.
