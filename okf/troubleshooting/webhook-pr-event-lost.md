---
type: Troubleshooting
title: PR 생성 webhook이 유실되어 PR이 Jenkins에 나타나지 않는다
description: 2026-10-03 PR #3의 pull_request.opened webhook이 연결 단계에서 실패해 Jenkins에 PR이 생기지 않았다. 원인은 확정하지 못했고 주기 스캔으로 보완했다.
tags: [jenkins, github, webhook, multibranch, troubleshooting]
timestamp: 2026-10-03T00:00:00+09:00
---

# 증상

2026-10-03 00:20 KST에 `vps-info` PR #3과 #4를 4분 간격으로 올렸다. #4는 `PR-4` 빌드가 돌고 GitHub에
commit status가 보고됐지만, #3은 Jenkins에 `PR-3`이 생기지 않고 필수 check가 `Expected`에 멈췄다.

# 조사

시각은 UTC 기준이다. GitHub 화면은 KST라서 9시간 차이가 난다.

| 시각 | 이벤트 | GitHub Recent Deliveries | VPS |
|---|---|---|---|
| 15:20:01 | #3 브랜치 push | 200 (2.82초) | nginx 200, Jenkins `Received PushEvent` |
| 15:20:12 | #3 `pull_request.opened` | `failed to connect to host` | nginx·Jenkins 기록 없음 |
| 15:24:16 | #4 브랜치 push | 200 | nginx 200 |
| 15:24:30 | #4 `pull_request.opened` | 200 | nginx 200, `PR-4` 생성 15:24:38 |

배제한 항목:

- **Jenkins·nginx 장애**: 해당 구간에 에러, 재시작, Docker 이벤트, OOM이 없다. Jenkins CPU 0.2%, 서버 load 0.2~0.5였다.
- **nginx 차단 설정**: `limit_req`와 IP 차단 규칙이 없다.
- **Tailscale**: webhook은 DNS로 풀린 공인 IP(eth0)로 직접 오고 Tailscale 대역을 거치지 않는다.
- **서버·개발자 위치**: webhook은 GitHub 서버가 VPS로 직접 보낸다. PR을 올린 위치와 무관하다.

# 원인

GitHub가 VPS에 TCP 연결을 맺지 못했다. 연결이 안 맺어지면 nginx에 요청이 오지 않으므로 서버 로그가 남지 않는다.
GitHub에서 VPS 공인 IP까지 구간의 일시 오류로 **추정**하며 확정하지 못했다. Hostinger 쪽 로그는 확인할 수 없다.

GitHub는 실패한 webhook을 자동으로 재시도하지 않고, 수동 Redeliver는 3일 안에만 가능하다. 그래서 한 번 실패하면 이벤트가
조용히 사라진다. 같은 계열의 간헐 실패 보고가 있다([community discussion](https://github.com/orgs/community/discussions/162643)).

# 조치

- 즉시: GitHub 저장소 Settings → Webhooks → Recent Deliveries에서 실패한 `pull_request` 건을 Redeliver 했다.
  `PR-3`이 생기고 빌드가 시작됐다.
- 재발 방지: `vps-info` multibranch에 15분 주기 스캔을 추가했다([ADR 0015](/adr/0015-multibranch-periodic-scan.md)).

# 다음에 같은 증상이면

PR이 Jenkins에 안 나타나면 위에서 아래로 확인한다.

```txt
GitHub Recent Deliveries의 해당 pull_request 상태
-> nginx 접근 로그의 POST /github-webhook/ 응답 코드 (docker logs vps-nginx)
-> Jenkins 로그의 Received PushEvent (docker logs vps-jenkins)
-> jobs/vps-info/branches/PR-N 존재 여부
```

Deliveries는 실패인데 nginx에 요청이 없으면 이 사례와 같은 연결 단계 실패다.

# 미확인

- 실패한 정확한 구간(GitHub 아웃바운드, 중간 네트워크, Hostinger 앞단).
- 모든 webhook 전송이 약 3초 걸리는 것이 이 실패와 관련 있는지. 서버 응답은 0.04~0.27초이고 GitHub의 제한은 10초라서 직접 원인으로 보기는 어렵다.
- 15분 스캔이 webhook 없이 PR을 실제로 잡는지 검증하지 않았다.
