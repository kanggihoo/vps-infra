---
type: Decision
title: SOPS 기반 secret 관리
description: secret을 SOPS + age로 암호화해 레포에 커밋하고, 복호화 key만 각 환경에 배치한다.
tags: [secrets, sops, age, security]
timestamp: 2026-08-23T00:00:00+09:00
---

# 결정

secret을 SOPS + age로 암호화해 레포에 커밋한다. 복호화 key는 로컬과 VPS에만 두고,
GitHub Secrets에는 그 key 하나만 저장한다.

암호화 대상:

```txt
.env               DB 비밀번호 등 런타임 secret
notes.htpasswd     notes 서브도메인 Basic Auth
github-pat         Jenkins가 checkout에 사용하는 credential
```

VPS의 age key 원본은 `~/.config/sops/age/keys.txt`에 둔다. 홈 디렉터리이므로 `sudo`가
필요 없다. Jenkins는 이 파일을 직접 읽지 않는다. 같은 key를 base64 한 줄로 만들어
`~/app/vps-infra/jenkins/.env`의 `SOPS_AGE_KEY_CONTENT`에 넣으면, JCasC가 이를
credential(secret file) `sops-age-key`로 등록하고 파이프라인이 그것으로 복호화한다.

# 이유

secret이 평문으로 VPS에만 존재하면 **로컬에서 같은 값을 재현할 수단이 없다.**
GitHub Secrets는 쓰기 전용이라 로컬 개발자가 읽을 수 없고, 결국 `.env`를 손으로 다시
만들게 된다. 그것이 현재 상태다.

암호화된 파일을 레포에 두면 로컬·CI·VPS가 **같은 파일 하나**를 보고 key만 각자
갖는다. 어떤 secret이 언제 바뀌었는지 git 이력에도 남는다.

현재 `/opt/nginx-auth/notes.htpasswd`가 root 소유 호스트 경로에 있어 로컬에서 재현할
수 없다. 이를 암호화해 레포에 넣으면 로컬에서도 같은 인증이 동작한다.

`github-pat`을 포함하는 이유는, Job이 코드로 복원되더라도 credential이 없으면
checkout이 실패해 반쪽 복구가 되기 때문이다.

# 결과

- age key를 분실하면 secret을 복호화할 수 없다. key 백업이 운영 요구사항이 된다.
- SOPS와 age 설치가 로컬·VPS·CI에 필요하다.
- key는 호스트의 두 파일(`keys.txt`, `jenkins/.env`)에 존재한다. 둘 다 `kkh`
  홈 아래에 있고 Git에 커밋되지 않는다. key를 교체하면 두 곳을 함께 바꾼다.
  Jenkins는 이미 `/var/run/docker.sock`을 통해 host Docker 제어 권한을 가지므로,
  credential로 key를 넘겨도 실질 권한이 늘어나지는 않는다.

# 거절한 대안

- **GitHub Actions Secrets만 사용**: 외부 도구가 없다는 장점이 있으나 값을 읽을 수
  없어 로컬 재현이 불가능하다.
- **Vault / Infisical**: 정석이지만 8GB VPS에 상주 프로세스가 추가되고, 그 프로세스가
  죽으면 배포가 멈춘다. Vault 하나가 portal과 redis를 합친 만큼의 메모리를 쓴다.
  현 규모에서 운영 비용이 이득을 넘는다.

# 관련 개념

- [Jenkins 설정을 코드로 관리](/adr/0009-jenkins-config-as-code.md)
- [Hostinger VPS](/environments/hostinger-vps.md)
