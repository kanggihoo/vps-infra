---
type: Decision
title: Jenkins를 VPS에서 걷어낸다
description: vps-info와 vps-infra 배포가 모두 GitHub Actions로 옮겨 Jenkins가 할 일이 없다. jenkins/ 설정, nginx 라우팅, 관측 스택의 Jenkins 수집을 지우고 컨테이너를 멈춘다.
tags: [jenkins, deployment, github-actions, cleanup]
timestamp: 2026-11-20T00:00:00+09:00
---

# 결정

Jenkins를 VPS 인프라에서 완전히 없앤다.

- `jenkins/` 디렉터리 전체를 지운다(`Dockerfile`, `compose.yml`, `casc/jenkins.yaml`, `casc/jobs.groovy`,
  shared library `notifyMattermost`, `plugins.txt`, `start.sh`, README). `Jenkinsfile`은 [ADR 0020](0020-infra-cd-on-github-actions.md)에서 이미 지웠다.
- nginx의 `nginx/templates/jenkins.conf.template`과 `vps_proxy`의 `jenkins.<도메인>` alias를 지운다.
  `jenkins.kkh-hub.tech` 요청은 이제 nginx default server(444)로 떨어진다.
- 관측 스택에서 Alloy의 Jenkins blackbox probe, Grafana 알림 규칙 "Jenkins 큐 적체", `Jenkins overview` 대시보드를 지운다.
  Alloy OTLP receiver는 nginx trace용으로 남기고, Jenkins가 보내던 데이터만 끊긴다.
- 병합 뒤 `vps-jenkins` 컨테이너를 멈추고 지웠다. volume(`vps_jenkins_data`, `vps_jenkins_data_pre_jcasc`)과 이미지도 지웠다.

배포 경로는 프로젝트마다 자기 레포의 GitHub Actions가 맡는다.

```txt
vps-info  main push -> check:task -> GHCR 이미지 -> ssh forced command ~/app/vps-info/scripts/deploy.sh "<sha> [erd]"  (ADR 0019)
vps-infra main push -> validate -> ssh forced command ~/app/vps-infra/scripts/ci-deploy.sh "<sha> <target>"     (ADR 0020)
```

# 이유

- [ADR 0006](0006-jenkins-builds-on-vps.md)이 Jenkins를 둔 근거는 학습이었고, 그 목적은 달성했다.
- Jenkins는 VPS에서 가장 큰 메모리 소비자였다(2026-11-20 1.41GiB / 상한 2GiB).
- [ADR 0019](0019-vps-info-cd-on-github-actions.md)·[ADR 0020](0020-infra-cd-on-github-actions.md) 이후 Jenkins가 실행하는 job이 없다.
  띄워 두면 메모리와 `docker.sock` 권한만 남는다.

# 결과

- Grafana에서 Jenkins OTel trace·메트릭·빌드 로그가 사라진다. 배포 로그는 각 레포의 Actions run에서 본다.
- Jenkins UI와 JUnit 결과 화면이 없어진다. 테스트 결과는 Actions 로그로 본다.
- 빌드 알림은 각 레포 workflow의 `notify` job이 보낸다([ADR 0012](0012-mattermost-build-notification.md)의 shared library는 지웠다).
- 빌드 기록은 volume과 함께 지웠다. 되돌릴 수 없다.
- 같은 날 정리를 마쳤다: VPS `jenkins/.env`(age key·PAT·관리자 비밀번호 평문 사본), 제한 없는 옛 배포 key(`github-actions-vps-infra`)와
  vps-infra secret `VPS_HOST`·`VPS_PORT`·`VPS_SSH_KEY`·`VPS_USER`, Jenkins checkout용 `secrets/github-pat.sops.txt`,
  `CHALLENGE_DOMAINS`와 인증서 SAN의 `jenkins.kkh-hub.tech`(인증서 재발급), 두 SOPS 파일의 Jenkins 주석.
- `jenkins.kkh-hub.tech` DNS A 레코드는 DNS 관리 화면에서 직접 지워야 한다. 지금은 nginx default server가 444로 끊는다.
- **배포 스크립트 자기 갱신 주의.** `scripts/ci-deploy.sh`와 vps-info `scripts/deploy.sh`는 VPS에 이미 있는 버전이 먼저 실행돼 새 커밋을 checkout한다.
  그래서 이 스크립트의 변경은 **다음 배포부터** 적용된다. 첫 전환 때도 같은 이유로 VPS에서 `git pull`을 한 번 손으로 했다.

# 관련 개념

- [vps-infra 배포를 GitHub Actions + SSH forced command로 옮긴다](0020-infra-cd-on-github-actions.md)
- [vps-info 배포를 GitHub Actions + GHCR + SSH forced command로 옮긴다](0019-vps-info-cd-on-github-actions.md)
- [Jenkins가 VPS에서 이미지를 빌드한다](0006-jenkins-builds-on-vps.md)
- [배포](../../okf/services/deploy.md)
