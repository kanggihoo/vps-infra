---
type: Decision
title: vps-infra 배포를 GitHub Actions + SSH forced command로 옮긴다
description: main push는 validate 뒤 Actions가 forced command로 묶인 key로 VPS의 scripts/ci-deploy.sh에 SHA와 대상만 넘긴다. Jenkinsfile의 순서를 그 스크립트가 그대로 실행한다.
tags: [deployment, github-actions, ssh, jenkins]
timestamp: 2026-11-20T00:00:00+09:00
---

# 결정

vps-infra의 main 배포를 Jenkins `vps-infra-pipeline`에서 이 레포의 `.github/workflows/validate.yml`로 옮긴다.
vps-info([ADR 0019](/adr/0019-vps-info-cd-on-github-actions.md))와 같은 방식이다. 이미지 레지스트리는 쓰지 않는다. portal·tools는 작고 드물게 바뀌어 VPS에서 그대로 빌드한다.

```txt
main push -> validate(compose·nginx 문법, seam 1·3, SOPS 암호화 확인)
          -> deploy: ssh kkh@VPS "<sha> <target>"
             -> authorized_keys forced command: ~/app/vps-infra/scripts/ci-deploy.sh
                -> flock /tmp/vps-deploy.lock -> checkout <sha>(main 이력만)
                -> 대상 판정(auto면 .deploy-state부터 select-target.sh, 없으면 all)
                -> tools 이미지로 secrets.sh decrypt(ENV_NAME=prod)
                -> deploy.sh <target> -> healthcheck.sh(127.0.0.1로 nginx에 직접) -> 성공 SHA 기록
          -> notify(Mattermost)
```

- **배포 key**: `~/.ssh/authorized_keys`에 `command="/home/kkh/app/vps-infra/scripts/ci-deploy.sh",restrict` 한 줄(comment `vps-infra-deploy`).
  private key는 vps-infra 레포 secret `VPS_DEPLOY_KEY`에만 있다.
- **수동 배포**: Jenkins의 `DEPLOY_TARGET` 파라미터는 `workflow_dispatch`의 `target`(auto|all|portal|observability)이 대신한다. 롤백은 VPS에서 `ci-deploy.sh <이전 SHA> all`이다.
- **SOPS**: Jenkins credential `sops-age-key` 대신 호스트의 `~/.config/sops/age/keys.txt`를 `tools` 컨테이너로 읽는다(`secrets.sh` 머리말의 기존 사용법).
- **healthcheck**: Jenkins 컨테이너 안에서는 `vps-nginx`로 붙었다. 호스트에서는 nginx가 publish한 443에 `127.0.0.1`로 붙는다(`HEALTHCHECK_CONNECT_HOST`).
- **직렬화**: vps-info 배포 스크립트와 같은 `/tmp/vps-deploy.lock`을 잡는다. Jenkins의 `numExecutors: 1`이 하던 일이다.
- **JCasC reload 단계**는 없앤다. Jenkins를 걷어내기 때문이다.
- `Jenkinsfile`을 삭제한다. 이 커밋부터 Jenkins는 배포하지 않는다.

# 이유

- vps-info를 옮긴 뒤 Jenkins가 하는 일은 vps-infra 배포 하나였고, 그 일은 셸 스크립트 순서라 Jenkins가 없어도 된다.
  Jenkinsfile 머리말대로 판정 로직은 이미 `scripts/`에 있어서 옮길 Groovy가 없었다.
- Jenkins는 VPS에서 가장 큰 메모리 소비자다(2026-11-20 1.41GiB / 상한 2GiB). 걷어내야 메모리 절감이 실제로 생긴다.
- 기존 `VPS_SSH_KEY`(ADR 0001 시절)는 제한 없는 key라 다시 쓰지 않고, forced command로 묶인 새 key를 만든다.

# 결과

- 배포 로그가 Actions에 모인다. Mattermost 알림은 workflow `notify` job이 보낸다(실패 단계·Actions 링크).
  Jenkins 알림의 실패 로그 꼬리·JUnit 요약은 없어진다.
- VPS checkout은 배포 뒤 detached HEAD다. `git log`로 배포된 커밋을 본다.
- Jenkins와 그 설정(`jenkins/`), nginx `jenkins` 라우팅, 관측 스택의 Jenkins 수집은 이어지는 정리에서 걷어낸다.

# 관련 개념

- [vps-info 배포를 GitHub Actions + GHCR + SSH forced command로 옮긴다](/adr/0019-vps-info-cd-on-github-actions.md)
- [Jenkins 내부 배포](/adr/0004-jenkins-deployment.md)
- [SSH Git-Pull 배포](/adr/0001-ssh-git-pull-deployment.md)
