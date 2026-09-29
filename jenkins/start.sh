#!/bin/sh
# 이미지의 plugins.txt만 설치 기준으로 삼는다(ADR 0009).
#
# 공식 jenkins.sh는 이미지의 /usr/share/jenkins/ref/plugins를 volume으로 복사만 하고
# 지우지는 않는다. 그래서 plugins.txt에서 뺀 plugin이 volume에 남아 계속 로드된다.
# 기동마다 volume의 plugins/만 비우고 다시 채운다. jobs/, credentials, secrets/는 건드리지 않는다.
set -eu
rm -rf "${JENKINS_HOME:?}/plugins"
exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
