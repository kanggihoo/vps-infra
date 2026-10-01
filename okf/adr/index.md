# 결정

아키텍처와 운영 결정 기록. 번호는 작성 시점 순이며, 새 결정은 다음 번호를 이어서 쓴다.

* [SSH Git-Pull 배포](0001-ssh-git-pull-deployment.md) - 폐기. GitHub Actions 배포 경로를 제거하고 검증 전용으로 전환한다.
* [공통 데이터 서비스](0002-shared-data-services.md) - PostgreSQL 컨테이너 1개와 Redis 컨테이너 1개를 운영하고, 향후 서비스별 논리 격리를 적용한다.
* [Docker 재시작 복구](0003-docker-restart-recovery.md) - Docker daemon boot enablement와 `restart: unless-stopped`를 사용한다.
* [Jenkins 내부 배포](0004-jenkins-deployment.md) - VPS 내부 Docker Jenkins가 webhook으로 배포를 실행한다. 일부 항목은 이후 결정으로 대체되었다.
* [서브도메인 라우팅](0005-subdomain-routing.md) - 초기 라우팅은 path prefix 대신 서브도메인을 사용한다.
* [Jenkins가 VPS에서 이미지를 빌드한다](0006-jenkins-builds-on-vps.md) - 빌드를 외부 CI로 넘기지 않고 VPS 내부 Jenkins가 직접 수행한다.
* [프로젝트별 독립 Compose](0007-per-project-compose.md) - 각 프로젝트가 자기 레포에서 compose와 이미지를 소유한다.
* [nginx 설정의 환경 템플릿화](0008-nginx-env-templates.md) - envsubst 템플릿 한 벌로 로컬과 VPS를 모두 커버한다.
* [Jenkins 설정을 코드로 관리](0009-jenkins-config-as-code.md) - JCasC와 job-dsl로 시스템 설정과 Job을 레포에서 관리한다.
* [SOPS 기반 secret 관리](0010-sops-secrets.md) - secret을 암호화해 레포에 커밋하고 복호화 key만 각 환경에 둔다.
* [인증서 갱신을 컨테이너 안에서 끝낸다](0011-certbot-container-renewal.md) - 상주 certbot이 갱신하고 nginx가 하루 한 번 스스로 reload한다.
* [빌드 결과를 Shared Library로 Mattermost에 알린다](0012-mattermost-build-notification.md) - implicit 라이브러리의 `notifyMattermost()`가 모든 job의 성공·실패를 한 채널에 보낸다.
* [DB 스키마 ERD를 Liam으로 빌드해 nginx에서 정적으로 서빙한다](0013-liam-erd-static-hosting.md) - 프로젝트 Jenkins job이 ERD를 빌드해 erd-site 볼륨에 넣고 nginx가 Basic Auth 뒤에서 서빙한다.
* [vps-info는 multibranch job으로 PR을 검증하고 main에서만 배포한다](0014-multibranch-pr-ci.md) - PR마다 Test를 돌려 필수 check로 보고하고, 배포 stage는 main 빌드에서만 실행한다.
