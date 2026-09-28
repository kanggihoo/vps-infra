# 버전 고정: lts-jdk21은 새 LTS 릴리스가 나오면 같은 태그가 다른 이미지를
# 가리키므로, Dockerfile이 바뀌지 않았는데도 로컬과 VPS가 다른 Jenkins를 갖는다.
FROM jenkins/jenkins:2.568.3-lts-jdk21

USER root

# Jenkins 파이프라인에서 호스트 Docker 데몬을 제어하기 위한 Docker CLI 및 Compose 플러그인 설치 (DooD 방식).
# Docker 데몬은 호스트의 /var/run/docker.sock을 공유하므로, 컨테이너 내부에는 명령을 실행할 CLI 도구만 설치한다.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg git \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# 프로젝트 파이프라인이 sops-age-key credential로 운영 .env를 복호화한다(ADR 0010).
# Debian 패키지가 없어 release 바이너리를 받고, 버전과 checksum을 고정한다.
ARG SOPS_VERSION=3.13.3
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) sum=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b ;; \
        arm64) sum=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77 ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /usr/local/bin/sops \
        "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${arch}" \
    && echo "${sum}  /usr/local/bin/sops" | sha256sum -c - \
    && chmod +x /usr/local/bin/sops

# 배포 경로의 부모 디렉터리를 jenkins 소유로 만든다.
# Jenkins의 dir() 스텝은 작업 디렉터리 옆에 "<dir>@tmp"를 만들므로
# 부모가 쓰기 가능해야 한다. root 소유면 AccessDeniedException이 난다.
RUN mkdir -p /app && chown jenkins:jenkins /app

USER jenkins

# plugin 설치. 최상위만 고정하고 하위 의존성은 CLI가 MANIFEST로 해석한다.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# JCasC 설정과 job-dsl 스크립트.
# /var/jenkins_home은 volume이라 런타임에 덮이므로 그 밖에 둔다.
# 이미지에 담아야 volume이 유실되어도 기동만으로 설정이 복원된다(ADR 0009).
COPY --chown=jenkins:jenkins jenkins.yaml /usr/share/jenkins/casc/jenkins.yaml
COPY --chown=jenkins:jenkins jobs.groovy /usr/share/jenkins/casc/jobs.groovy
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml

# 초기 설정 위저드 건너뛰기와 heap 상한은 compose의 JAVA_OPTS에서 준다.
# 여기서 ENV로 두면 compose 값이 이 값을 덮어써 혼동을 만든다.
