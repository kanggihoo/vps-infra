---
type: Decision
title: Jenkins 설정을 코드로 관리
description: JCasC와 job-dsl로 Jenkins 시스템 설정과 Job 정의를 레포에서 관리하고, GUI는 편집 수단으로 쓰지 않는다.
tags: [jenkins, jcasc, job-dsl, configuration-as-code]
timestamp: 2026-08-23T00:00:00+09:00
---

# 결정

Jenkins 시스템 설정과 Job 정의를 `jenkins/jenkins.yaml`(Configuration as Code)과
job-dsl로 레포에서 관리한다. plugin 목록은 `jenkins/plugins.txt`에 **최상위 plugin만**
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

- **GUI에서 변경한 설정은 재기동 시 사라진다.** JCasC가 관리하는 항목을 기동 시
  덮어쓰기 때문이다. 설정 변경은 항상 `jenkins.yaml` 수정 → 커밋 → 배포로 한다.
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

# 거절한 대안

- **multibranch / organization folder**: Job 정의가 아예 불필요해지지만 프로젝트
  레포가 여러 곳에 흩어져 organization 단위 스캔이 맞지 않고 GitHub API 사용량이
  늘어난다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [Jenkins가 VPS에서 이미지를 빌드한다](/adr/0006-jenkins-builds-on-vps.md)
- [SOPS 기반 secret 관리](/adr/0010-sops-secrets.md)
