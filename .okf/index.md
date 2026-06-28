---
okf_version: "0.1"
---

# VPS 인프라 지식 번들

Hostinger VPS 인프라 프로젝트의 핵심 지식을 담는 OKF 번들.

# 그룹

* [서비스](services/) - VPS 인프라가 운영하는 런타임 구성요소.
* [결정](decisions/) - 1차 단계에서 확정한 아키텍처와 운영 결정.
* [런북](runbooks/) - 배포 검증과 장애 진단 절차.
* [환경](environments/) - 배포 대상 VPS와 public 운영 메타데이터.
* [참고 문서](references/) - OKF 개념이 근거로 삼는 원본 문서.

# 핵심 개념

* [GitHub Actions 배포](services/github-actions-deploy.md) - `main` 변경 시 GitHub Actions가 SSH로 VPS에 접속해 배포한다.
* [Traefik 리버스 프록시](services/traefik.md) - VPS의 public HTTP/HTTPS 진입점.
* [Hostinger VPS](environments/hostinger-vps.md) - 현재 인프라가 배포될 VPS와 public 운영 메타데이터.
* [초기 배포 검증](runbooks/initial-deployment-validation.md) - 첫 인프라 배포 성공 기준.
