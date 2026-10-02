# 트러블슈팅

운영 중 겪은 문제의 증상, 조사 과정, 원인, 조치를 사례 하나당 파일 하나로 기록한다. 결정은 [ADR](../adr/)에,
반복 가능한 진단 절차는 [런북](../runbooks/)에 두고 여기서는 링크한다.

* [PR 생성 webhook이 유실되어 PR이 Jenkins에 나타나지 않는다](webhook-pr-event-lost.md) - GitHub가 연결 단계에서 실패한 webhook을 재시도하지 않아 PR #3만 누락됐고, 15분 주기 스캔으로 보완했다.
