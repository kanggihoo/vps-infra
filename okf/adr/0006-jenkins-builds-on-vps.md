---
type: Decision
title: Jenkins가 VPS에서 이미지를 빌드한다
description: 빌드를 외부 CI나 registry로 넘기지 않고 VPS 내부 Jenkins가 webhook을 받아 직접 빌드한다.
tags: [deployment, jenkins, ci, build]
timestamp: 2026-08-23T00:00:00+09:00
---

# 결정

각 프로젝트의 Docker 이미지 빌드는 VPS 내부 Jenkins가 수행한다. GitHub Actions로
빌드를 옮기고 GHCR에서 `docker pull`만 하는 방식은 채택하지 않는다.

# 이유

**Jenkins 학습이 이 인프라의 목적 중 하나다.** 빌드를 Actions로 넘기면 Jenkins가
`docker pull && up -d`만 실행하는 껍데기가 되고, 그건 SSH 한 줄로도 되는 일이다.
Pipeline, credential, 빌드 캐시, 동시성 제어 같은 주제는 Jenkins가 실제로 빌드를
수행할 때만 다루게 된다.

리소스 실측이 이 선택을 뒷받침한다(2026-08-22 기준).

```txt
메모리   7.9GB 중 2.0GB 사용 (Jenkins 1.0GB, 그 외 전부 합쳐 ~40MB)
CPU     상시 0%대
디스크   96GB 중 12GB (13%)
```

여유가 5.8GB이므로 2 코어 빌드 부담은 현 단계에서 실측 근거가 없는 우려다.

# 결과

- 배포 중 2 코어가 컴파일에 점유된다. Quartz 빌드는 약 3분이 걸린다.
- 프로젝트가 늘어 동시 빌드가 경합하면 빌드만 Actions로 옮긴다. 그 이동은
  Jenkinsfile의 build stage를 제거하는 수준이므로 되돌리기 비용이 낮다.
- Jenkins가 유일한 변동성 큰 메모리 소비자이므로 Jenkins에만 `mem_limit`과
  JVM heap 상한을 둔다. VPS에 swap이 없어 OOM이 발생하면 프로세스가 즉시 죽는다.

# 거절한 대안

- **GHCR + Actions 빌드**: VPS CPU 부담이 사라지고 로컬과 VPS가 동일 이미지를
  실행하는 이점이 있다. Jenkins의 역할이 사라져 학습 목적과 충돌하므로 거절했다.
- **로컬 빌드 후 `docker save`로 전송**: registry가 불필요하지만 push 기반 자동
  배포가 사라진다.

# 관련 개념

- [Jenkins 배포](/services/jenkins-deploy.md)
- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
