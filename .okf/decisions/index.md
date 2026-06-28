# 결정

* [SSH Git-Pull 배포](ssh-git-pull-deployment.md) - GitHub Actions가 SSH로 VPS에 접속하고 VPS에서 `git pull`을 실행한다.
* [서브도메인 라우팅](subdomain-routing.md) - 초기 Traefik 라우팅은 path prefix 대신 서브도메인을 사용한다.
* [공통 데이터 서비스](shared-data-services.md) - PostgreSQL 컨테이너 1개와 Redis 컨테이너 1개를 운영하고, 향후 서비스별 논리 격리를 적용한다.
* [Docker 재시작 복구](docker-restart-recovery.md) - Docker daemon boot enablement와 `restart: unless-stopped`를 사용한다.
