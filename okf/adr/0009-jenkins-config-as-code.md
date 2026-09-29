---
type: Decision
title: Jenkins 설정을 코드로 관리
description: JCasC와 job-dsl로 Jenkins 시스템 설정과 Job 정의를 레포에서 관리하고, GUI는 편집 수단으로 쓰지 않는다.
tags: [jenkins, jcasc, job-dsl, configuration-as-code]
timestamp: 2026-09-29T00:00:00+09:00
---

# 결정

Jenkins 시스템 설정과 Job 정의를 `jenkins/casc/jenkins.yaml`(Configuration as Code)과
`jenkins/casc/jobs.groovy`(job-dsl)로 레포에서 관리한다. plugin 목록은 `jenkins/plugins.txt`에 **최상위 plugin만**
버전을 고정해 적고, 하위 의존성은 `jenkins-plugin-cli`가 자동 해석한다.

# 이유

현재 Jenkins 설정은 전부 VPS UI의 수동 작업이며 레포에 없다.

```txt
Job          quartz-deploy, vps-infra-pipeline  (레포에 정의 없음)
plugin       94개                               (목록 없음)
credential   github-pat                         (Jenkins 내부에만 존재)
```

volume이 유실되면 전부 수작업으로 복구해야 한다. 더 중요한 문제는 **로컬 Jenkins에서
파이프라인을 테스트할 때마다 Job을 손으로 만들어야 한다**는 점이다. 이것이 로컬 검증
목표를 무너뜨리는 지점이다.

Job까지 코드화해야 로컬 Jenkins가 `up -d` 한 번으로 VPS와 같은 상태가 된다.
JCasC를 시스템 설정에만 적용하고 Job을 GUI에 남기면 이 이점을 얻지 못한다.

# 결과

- **GUI에서 변경한 설정은 reload나 재기동 시 사라진다.** JCasC가 관리하는 항목을
  그때마다 덮어쓰기 때문이다. 설정 변경은 항상 `jenkins/casc/` 수정 → 커밋 → push로 한다.
  GUI는 조회와 빌드 실행에만 쓴다. 이 제약이 JCasC의 대가다.
- `configuration-as-code`와 `job-dsl` plugin은 현재 미설치이므로 새로 추가한다.
  즉 기존 94개 목록을 그대로 고정하는 선택지는 성립하지 않는다.
- 최상위만 버전을 고정하므로 **하위 의존성 버전은 고정되지 않는다.** 가독성을 위한
  의식적 trade-off다. 의존성 버전 차이로 문제가 생기면 그 항목만 추가로 고정한다.
- Jenkins base image도 버전 태그로 고정한다. `lts-jdk21` 같은 태그는 새 릴리스가
  나오면 같은 태그가 다른 이미지를 가리키므로, Dockerfile이 바뀌지 않았는데도
  로컬과 VPS가 다른 Jenkins를 갖게 된다. 같은 이유로 `certbot/certbot`(태그 없음
  = `latest`), `nginx:alpine` 등 다른 image에도 버전을 명시한다.
- JCasC 전환 시 기존 수동 설정과 충돌할 수 있다. 로컬에서 먼저 구축해 충돌을
  겪고, VPS 적용 전에 Jenkins volume을 백업한다.

# 설정 파일 전달 방식 (2026-09-29 변경)

처음에는 `jenkins.yaml`과 `jobs.groovy`를 이미지에 `COPY`했다. volume이 유실되어도
이미지만으로 설정이 복원된다는 이유였다. 그러나 Job 하나를 추가해도 VPS에 SSH로 들어가
재빌드해야 했고, 컨테이너 교체 동안 Jenkins가 내려가 webhook을 놓칠 수 있었다.
오픈소스 Jenkins는 컨트롤러가 하나라 이 다운타임을 없앨 방법이 없다.

그래서 두 파일을 `jenkins/casc/`로 옮기고 이 폴더를 컨테이너의 `/usr/share/jenkins/casc`에
read-only로 마운트한다. vps-infra 파이프라인은 `git pull`로 checkout을 갱신한 뒤 마지막 단계에서
token reload endpoint(`CASC_RELOAD_TOKEN`)로 JCasC를 다시 읽힌다. reload는 재시작이 아니므로
다운타임이 없다.

- 파일이 아니라 폴더를 마운트한다. `git pull`은 파일을 새로 만들어 바꿔치기하므로 파일 단위
  bind mount는 옛 inode를 계속 보여준다.
- volume 유실 시 복원 근거는 이미지에서 VPS checkout으로 옮겨진다. checkout은 배포에 어차피
  필요하므로 새로 생기는 위험은 작다. 대신 VPS checkout을 직접 고치면 Jenkins 설정이 레포와
  어긋날 수 있다.
- `plugins.txt`와 `Dockerfile`은 빌드 때 설치가 일어나므로 계속 이미지에 둔다. 이것과
  `jenkins/.env`를 바꿀 때만 재빌드나 재기동이 필요하다. 새 plugin을 쓰는 설정은 plugin 반영
  (재빌드) 후에 push해야 reload가 실패하지 않는다.
- 놓친 webhook을 되살리는 `pollSCM`이나 기동 시 1회 확인은 실제 유실이 생기기 전까지 두지 않는다.

# plugin 정리 (2026-09-29)

- 제거: `ws-cleanup`(`cleanWs()`를 쓰지 않음), `build-timeout`(freestyle용. pipeline `timeout()`은
  기본 스텝), `docker-workflow`(docker를 `sh`로만 호출).
- 추가: `pipeline-graph-view`(단계별 그래프), `ansicolor`(콘솔 색상), `junit`(테스트 결과 추이,
  [ADR 0012](/adr/0012-mattermost-build-notification.md)의 실패 테스트 요약). `junit`은 이미 하위
  의존성으로 설치되어 있었지만 직접 쓰므로 최상위에 고정한다.
- **기동마다 volume의 `plugins/`를 비운다(`jenkins/start.sh`).** Jenkins는 plugin을 `JENKINS_HOME/plugins`에서만
  읽고, 공식 `jenkins.sh`는 이미지의 `/usr/share/jenkins/ref/plugins`를 그곳으로 복사만 하고 지우지 않는다.
  그래서 `plugins.txt`에서 뺀 plugin이 volume에 남아 계속 로드됐다. 이제 `plugins.txt`가 실제 설치 목록이고
  추가·업그레이드·삭제 모두 재빌드로 끝난다. GUI로 설치한 plugin은 재기동 때 사라지며, 이는 JCasC 원칙과 같다.
  기동 때 전체 plugin을 다시 복사하므로 기동이 조금 느려진다.

# 거절한 대안

- **multibranch / organization folder**: Job 정의가 아예 불필요해지지만 프로젝트
  레포가 여러 곳에 흩어져 organization 단위 스캔이 맞지 않고 GitHub API 사용량이
  늘어난다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
