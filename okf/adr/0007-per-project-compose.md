---
type: Decision
title: 프로젝트별 독립 Compose
description: 각 프로젝트가 자기 레포에서 compose와 이미지를 소유하고, vps-infra는 공통 기반만 관리한다.
tags: [deployment, docker-compose, ownership, nginx]
timestamp: 2026-08-23T00:00:00+09:00
---

# 결정

각 프로젝트는 자기 레포에 `Dockerfile`과 `compose.yml`을 두고, `vps_proxy`
네트워크를 `external: true`로 참조한다. `vps-infra`는 공통 기반만 소유한다.

```txt
vps-infra        nginx, certbot, postgres, redis, jenkins (+ portal 예외)
프로젝트 레포     자기 Dockerfile + compose.yml + Jenkinsfile
```

이는 기존 방침(`INFRA.md` 2-2: "특별한 이유가 없으면 루트 `compose.yml`에 추가")을
뒤집는다.

# 이유

중앙집중 방식은 **다른 레포의 프로젝트를 배포하는 데 `vps-infra` 수정 권한이
필요하다**는 결합을 만든다. 프로젝트가 늘어날수록 이 레포가 병목이 된다.

Jenkins를 별도 Compose project로 분리한 이유(배포 중 자기 자신이 재생성되는 문제)와
같은 논리가 모든 프로젝트에 적용된다. 한 프로젝트의 배포가 다른 프로젝트를 건드리지
않아야 한다.

# 결과

- Quartz 노트가 이 원칙의 첫 적용 대상이다. 지금은 Jenkins가 빌드 산출물을 호스트
  `/opt/quartz-site`에 놓고 nginx가 bind mount로 직접 서빙하는데, 이를
  `nginx:alpine` 기반 이미지에 정적 파일을 담아 `vps_proxy`에 붙이는 방식으로
  바꾼다. `Dockerfile`과 `compose.yml`은 `quartz-site-private` 레포가 소유한다.
  이로써 호스트 경로 의존이 사라지고 **이전 이미지 태그로 되돌리는 rollback**이
  생긴다. 현재는 빌드가 깨지면 재빌드 외에 복구 수단이 없다.
- nginx 설정은 80/443을 단독 점유하므로 `vps-infra`에 남는다. 서비스 1개 =
  템플릿 파일 1개 규칙을 유지한다.
- `portal`은 예외로 `vps-infra`에 유지한다. 인프라 자체를 보여주는 대시보드여서
  생명주기가 `vps-infra`와 같다. 서비스 목록이 바뀌면 둘 다 바뀐다.

# 관련 개념

- [서브도메인 라우팅](/adr/0005-subdomain-routing.md)
- [nginx 설정의 환경 템플릿화](/adr/0008-nginx-env-templates.md)
- [nginx 리버스 프록시](/services/nginx.md)
