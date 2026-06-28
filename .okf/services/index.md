# 서비스

* [GitHub Actions 배포](github-actions-deploy.md) - `main` 변경 시 GitHub Actions가 SSH로 VPS에 접속해 배포한다.
* [Traefik 리버스 프록시](traefik.md) - VPS의 public HTTP/HTTPS 진입점.
* [whoami Health Target](whoami.md) - DNS, TLS, Traefik 라우팅, Docker 네트워크를 검증하는 가벼운 HTTP 컨테이너.
* [PostgreSQL](postgresql.md) - 향후 서비스별 DB를 담을 공통 PostgreSQL 컨테이너.
* [Redis](redis.md) - 향후 서비스 캐시/세션 용도로 쓸 공통 Redis 컨테이너.
