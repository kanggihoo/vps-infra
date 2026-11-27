# Tinyauth SSO evidence

운영 VPS(`kkh-hub.tech`) 수동 검증 기록. 모든 단계는 main `f00d99a`(PR #7 + #8 배포, Infra deploy run 46025885362)에 대해 실행했다.
공개 레포이므로 보호 콘텐츠(notes, info) 화면과 개인 이메일이 보이는 화면은 커밋하지 않고 본문에 결과만 적는다.

## AC-10, 2026-11-28, f00d99a
Step: main merge로 GitHub Actions `Infra deploy`가 `ci-deploy.sh` → `deploy.sh all`을 실행했다. 운영 `.env`는 실제 계정·화이트리스트·Google client를 담고 있다.
Saw: 배포 가드를 통과해 스택이 적용되었다. 로그에 `[deploy] adding to certificate: auth.kkh-hub.tech`, `Renewing an existing certificate for kkh-hub.tech and 7 more`, `Successfully received certificate`가 찍혔다. `auth.kkh-hub.tech` 인증서 SAN에 auth를 포함한 8개 도메인이 있고 만료는 2027-02-25다. 가드가 막는 쪽(빈 계정, test 계정, 빈 화이트리스트, 따옴표 없는 `$`)은 `scripts/test-deploy-guards.sh`가 CI에서 확인한다.
Artifacts: evidence/prod-curl.txt

## AC-11, 2026-11-28, f00d99a
Step: 같은 배포의 `healthcheck.sh`(HEALTHCHECK_CONNECT_HOST=127.0.0.1) 결과를 보고, 로컬 PC에서 공개 주소로 curl을 보냈다.
Saw: healthcheck가 `auth route`, `erd|notes|info|grafana redirects to login`, `grafana internal health (http://grafana:3000/api/health)`를 모두 통과하고 `[healthcheck] ok`로 끝났다. 공개 curl로 erd·notes·info·grafana는 `302 https://auth.kkh-hub.tech/login?redirect_uri=...`, auth·portal·health는 200이었다. Alloy의 auth·grafana probe는 같은 배포로 재생성된 Alloy가 적용한다.
Artifacts: evidence/prod-curl.txt

## AC-3, 2026-11-28, f00d99a
Step: ego-browser로 `https://erd.kkh-hub.tech/`를 열어 `auth.kkh-hub.tech/login?redirect_uri=https://erd.kkh-hub.tech/`로 이동한 것을 확인했다. 운영자가 로컬 계정으로 로그인한 뒤, 같은 브라우저 세션으로 erd·notes·info·grafana를 차례로 열었다. 운영자는 화이트리스트 Gmail로 Google 로그인도 직접 성공시켰다.
Saw: 로그인 화면에 Google 버튼과 아이디/비밀번호 폼이 함께 나왔다. 로컬 계정 로그인 후 erd("Index of /", vps-info/), notes(Quartz Home), info(vps-info 앱), grafana(Home)가 재로그인 없이 열렸다. grafana `/api/user`는 `authLabels: ["Auth Proxy"]`, `/api/user/orgs`는 `role: Admin`이었다. `auth.kkh-hub.tech/logout`에서 로그아웃하자 erd가 다시 로그인으로 302 되었다. Google 로그인 후 로그아웃 화면에 "Google OAuth 제공자를 통해 (화이트리스트 이메일)로 로그인되어 있습니다"가 표시되었다.
Artifacts: evidence/sso-erd.png, evidence/sso-grafana.png

## AC-4, 2026-11-28, f00d99a
Step: 운영자가 Google 세션이 없는 시크릿 창에서 `https://erd.kkh-hub.tech/`를 열고, 화이트리스트에 없는 Google 계정(학교 계정)으로 Google 로그인했다.
Saw: Tinyauth가 "권한 없음 — 사용자 이름 (해당 이메일)은(는) 로그인할 권한이 없습니다." 화면을 보여 주고 erd로 넘어가지 않았다. 화면은 이메일이 보여 커밋하지 않았다(운영자 대화에 첨부).
Artifacts: 없음
