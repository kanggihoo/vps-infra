# 스크립트 실행 진입점. 호스트 셸 종류(PowerShell/zsh)와 무관하게 만든다.
# 호스트에서는 `docker compose run --rm tools ...`만 실행한다.
FROM alpine:3.24

# git       배포 대상 판정에 필요
# bash      스크립트가 bash 기준
# curl      헬스체크와 seam 2 검증
# docker-cli+compose  docker.sock을 통해 호스트 Docker를 제어
# sops, age secret 복호화 (단계 3)
RUN apk add --no-cache \
      bash \
      git \
      curl \
      docker-cli \
      docker-cli-compose \
      sops \
      age

WORKDIR /repo

ENTRYPOINT ["/bin/bash"]
