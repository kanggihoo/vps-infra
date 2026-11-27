---
type: Decision
title: vps-info 배포를 GitHub Actions + GHCR + SSH forced command로 옮기고 Jenkins job을 없앤다
description: vps-info 이미지는 Actions가 빌드해 GHCR에 올리고, VPS는 forced command로 묶인 배포 key로 받은 SHA를 pull해 배포한다. jobs.groovy의 vps-info job을 지운다.
tags: [deployment, github-actions, ghcr, ssh, jenkins, vps-info]
timestamp: 2026-11-20T00:00:00+09:00
---

# 결정

`vps-info`의 main 배포를 Jenkins `vps-info` multibranch job에서 vps-info 레포의 GitHub Actions(`ci.yml`)로 옮긴다.
결정의 앱 쪽 내용은 vps-info `docs/adr/0020-build-images-in-actions-and-deploy-over-ssh.md`에 있고, 여기에는 VPS와 이 레포가 갖는 부분을 적는다.

```txt
vps-info main push -> Actions: check:task -> image(ghcr.io/kanggihoo/vps-info:<sha>-<서비스> push)
                   -> deploy: ssh kkh@VPS "<sha> [erd]"
                      -> authorized_keys forced command: ~/app/vps-info/scripts/deploy.sh
                         -> flock /tmp/vps-deploy.lock -> checkout <sha> -> sops 이미지로 .env -> compose pull -> up --wait -> (ERD)
                   -> notify(Mattermost CD)
```

- **VPS 배포 key**: `~/.ssh/authorized_keys`에 `command="/home/kkh/app/vps-info/scripts/deploy.sh",restrict` 한 줄(comment `vps-info-deploy`).
  이 key로는 셸, 다른 명령, 포트 포워딩이 안 된다. private key는 vps-info 레포 secret `VPS_DEPLOY_KEY`에만 있다.
- **VPS checkout**: `~/app/vps-info`(GitHub https clone, 인증 없음). Jenkins workspace를 쓰지 않는다. compose 프로젝트 이름이 `vps-info`로 고정이라
  컨테이너와 `vps-info_llm_auth` 볼륨을 그대로 이어받는다.
- **SOPS key**: 호스트의 `~/.config/sops/age/keys.txt`를 쓴다. sops는 호스트에 설치하지 않고 `ghcr.io/getsops/sops:v3.13.3-alpine`으로 실행한다.
  Jenkins credential `sops-age-key`는 vps-infra 파이프라인만 쓴다.
- **직렬화**: 배포 스크립트는 `/tmp/vps-deploy.lock`을 `flock`으로 잡는다. Jenkins의 `numExecutors: 1`을 대신한다.
  vps-infra 파이프라인은 아직 이 lock을 잡지 않으므로, 둘이 겹치면 서로 기다리지 않는다(vps-infra 이전 때 같은 lock을 쓴다).
- **이미지**: GHCR 패키지 `ghcr.io/kanggihoo/vps-info` 하나, public. VPS는 로그인하지 않는다. VPS는 배포한 태그 말고는 지운다.
- **Jenkins**: `jobs.groovy`에서 `vps-info` multibranch job을 지우고, 그 job만 쓰던 `github-branch-source` plugin을 `plugins.txt`에서 뺀다.

# 이유

- Jenkins는 VPS 메모리를 가장 많이 쓰고([ADR 0006](0006-jenkins-builds-on-vps.md)), BuildKit 빌드는 그 상한 밖에서 돈다. 빌드를 VPS 밖으로 빼면 배포 때 VPS에는 pull과 재시작만 남는다.
- PR 검증을 Actions로 옮긴 뒤([ADR 0018](0018-vps-info-pr-ci-on-github-actions.md)) CD만 Jenkins에 남아 로그가 두 곳에 나뉘었다.
- self-hosted runner는 vps-info가 public 레포라 위험하다(PR이 workflow를 고쳐 docker socket 권한으로 코드를 실행할 수 있다).
  forced command로 묶인 SSH key는 상주 프로세스가 없고, 새도 main 이력의 커밋을 배포하는 것 말고는 할 수 없다.
- [ADR 0001](0001-ssh-git-pull-deployment.md)의 SSH 배포를 폐기한 이유(배포 경로 이중 유지, `github.event.before`가 비는 버그)는 여기에 해당하지 않는다.
  배포 경로는 하나이고, 배포할 SHA는 Actions가 넘기는 `github.sha`다.

# 결과

- 전환은 2026-11-20 vps-info PR #30 병합으로 했다. 그 커밋부터 main에 `Jenkinsfile`이 없어 Jenkins는 빌드하지 않는다.
  병합 전에 VPS에서 `deploy.sh`를 수동 실행해 GHCR 이미지로 교체되는 것을 확인했고(42초), 병합 뒤 첫 Actions 배포는 check부터 deploy까지 약 4분이었다.
- Jenkins는 이제 vps-infra 파이프라인만 실행한다. `jobs.groovy`에서 지운 job이 JCasC reload 뒤에도 남아 있으면 Jenkins에서 한 번 직접 지운다.
- vps-info GitHub webhook(`jenkins.kkh-hub.tech/github-webhook/`)은 더는 쓰지 않는다. Jenkins job을 지운 뒤 함께 지운다.
- vps-info의 ERD는 Jenkins stage가 아니라 `scripts/erd.sh`가 만든다([ADR 0013](0013-liam-erd-static-hosting.md)의 산출물 위치·서빙 방식은 그대로다).
- 남은 일: vps-infra 배포도 같은 방식으로 옮기고 Jenkins를 걷어낸다. 그때 이 lock을 vps-infra 배포 스크립트도 잡는다.

# 관련 개념

- [vps-info PR 검증을 GitHub Actions로 옮기고 Jenkins는 main 배포만 한다](0018-vps-info-pr-ci-on-github-actions.md)
- [Jenkins가 VPS에서 이미지를 빌드한다](0006-jenkins-builds-on-vps.md)
- [SOPS 기반 secret 관리](0010-sops-secrets.md)
- [vps-info (Signal Archive)](../../okf/services/vps-info.md)
