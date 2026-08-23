# 버전 고정: lts-jdk21은 새 LTS 릴리스가 나오면 같은 태그가 다른 이미지를
# 가리키므로, Dockerfile이 바뀌지 않았는데도 로컬과 VPS가 다른 Jenkins를 갖는다.
FROM jenkins/jenkins:2.568.2-lts-jdk21

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg git \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

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
