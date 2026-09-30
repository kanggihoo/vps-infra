# 서비스

* [Jenkins 배포](jenkins-deploy.md) - VPS 내부 Jenkins가 GitHub webhook으로 Docker Compose를 실행한다.
* [GitHub Actions 검증](github-actions-deploy.md) - 현재 push/PR 설정 검증과 과거 SSH 배포 기록.
* [nginx 리버스 프록시](nginx.md) - VPS의 public HTTP/HTTPS 진입점.
* [공용 인프라 포털](portal.md) - 현재 구현된 public service 링크와 curated skill markdown library를 제공하는 React+Go 기반 포털.
* [vps-info (Signal Archive)](vps-info.md) - 자기 레포에서 compose와 Jenkinsfile을 소유하고 공용 PostgreSQL과 nginx를 쓰는 첫 외부 프로젝트.
* [ERD 서빙 (Liam ERD)](erd.md) - 프로젝트 DB 스키마의 ER 다이어그램을 erd 서브도메인에서 정적 파일로 제공한다.
* [whoami Health Target](whoami.md) - DNS, TLS, nginx 라우팅, Docker 네트워크를 검증하는 가벼운 HTTP 컨테이너.
* [PostgreSQL](postgresql.md) - 향후 서비스별 DB를 담을 공통 PostgreSQL 컨테이너.
* [Redis](redis.md) - 향후 서비스 캐시/세션 용도로 쓸 공통 Redis 컨테이너.
