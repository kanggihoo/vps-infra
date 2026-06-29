VPS 공통 인프라는 앱 코드와 분리된 별도 디렉토리 또는 GitHub repository로 관리하고, reverse proxy, 인증 게이트웨이, 공통 네트워크, 배포 규칙을 한 곳에서 소유한다.

## VPS 인프라 운영 스펙

이 문서는 하나의 VPS에서 Docker 기반으로 여러 프로젝트를 운영할 때, 공통 인프라를 어떻게 분리하고 배포할지에 대한 기준을 정의한다.

### 기본 결정

- **인프라 관리 위치:** `vps-infra` 디렉토리 또는 별도 GitHub repository
- **앱 관리 위치:** 각 앱별 별도 repository
- **공통 진입점:** reverse proxy가 `80/443` 포트를 단독으로 노출
- **인증 방식:** 공개 경로는 통과, 보호 경로는 SSO/Auth Gateway 적용
- **앱 접근 방식:** 앱 컨테이너는 public port를 열지 않고 Docker internal network로만 접근
- **배포 방식:** GitHub Actions 또는 SSH 기반 `git pull && docker compose up -d`

### 권장 디렉토리 구조

```txt
vps-infra/
  README.md
  compose.yml
  .env.example
  traefik/
    traefik.yml
    dynamic.yml
  authentik/
    README.md
  scripts/
    deploy.sh
    backup.sh
```

앱별 repository는 인프라 repository와 분리한다.

```txt
app1/
  Dockerfile
  compose.yml
  src/

app2/
  Dockerfile
  compose.yml
  src/
```

### Repository 분리 기준

| 구분 | 관리 위치 | 포함 내용 |
|---|---|---|
| 공통 인프라 | `vps-infra` | reverse proxy, SSO, 공통 network, TLS, monitoring, 공통 deploy script |
| 앱 코드 | 앱별 repo | Spring, FastAPI, React, DB migration, 앱 전용 compose |
| 민감 정보 | VPS 내부 또는 secret manager | `.env`, private key, DB password, session secret |

인프라 repository에는 실제 비밀값을 넣지 않는다. Git에는 `.env.example`만 저장하고, 운영 서버에는 실제 `.env`를 별도로 둔다.

### Docker 네트워크 전략

공통 reverse proxy가 앱 컨테이너를 찾을 수 있도록 외부 Docker network를 하나 둔다.

```bash
docker network create proxy
```

인프라 compose와 앱 compose는 같은 external network를 공유한다.

```yaml
networks:
  proxy:
    external: true
```

앱은 reverse proxy와 통신하기 위한 `proxy` network와, 앱 내부 DB 통신을 위한 private network를 분리해서 사용한다.

```txt
traefik -> proxy network -> app1
app1 -> app1_internal network -> app1-db
```

### Reverse Proxy 역할

Reverse proxy는 모든 외부 요청의 첫 진입점이다.

- TLS 종료
- 도메인 기반 라우팅
- path 기반 라우팅
- SSO/Auth Gateway 연동
- public/private route 분리
- 기존 사용자 전달 header 제거 후 재설정

예시 라우팅:

```txt
app1.example.com             -> app1 public
app1.example.com/admin       -> SSO 보호
app2.example.com             -> app2 public
tools.example.com            -> SSO 보호
auth.example.com             -> Authentik
```

### SSO와 앱 인증 경계

SSO는 사용자가 누구인지 확인하고, 앱은 해당 사용자가 앱 안에서 무엇을 할 수 있는지 판단한다.

| 영역 | 담당 |
|---|---|
| 로그인 | Authentik, Authelia, Keycloak 같은 IdP |
| MFA | IdP |
| 공통 그룹 | IdP |
| JWT 발급 | IdP |
| JWT 검증 | Gateway 또는 앱 |
| 앱 내부 권한 | 각 앱 |
| 도메인 데이터 권한 | 각 앱 |

권장 방식:

- 내부 관리자 도구: Gateway auth + trusted header
- 중요한 API: Bearer JWT pass-through + 앱에서도 JWT 검증
- 서비스 사용자 기능: 앱 자체 권한 모델 또는 OIDC 기반 로그인

### Authentik DB와 앱 DB 경계

Authentik은 자체 DB를 가진다. 이 DB는 인증 서버의 내부 상태 저장소이며 앱이 직접 조회하지 않는다.

Authentik DB가 관리하는 정보:

- 계정
- 비밀번호 hash
- MFA 설정
- 세션
- OAuth/OIDC client
- 그룹
- 인증 정책

앱 DB가 관리하는 정보:

- 앱 내부 사용자 PK
- `auth_subject`
- 앱별 권한
- 사용자 설정
- 게시글, 주문, 프로젝트 같은 도메인 데이터

앱의 최소 사용자 테이블:

```sql
create table app_users (
  id bigserial primary key,
  auth_subject varchar(255) unique not null,
  created_at timestamp not null,
  last_seen_at timestamp
);
```

요청 처리 흐름:

1. 사용자가 Authentik에서 로그인한다.
2. 클라이언트가 `Authorization: Bearer <JWT>`로 앱에 요청한다.
3. Gateway 또는 앱이 JWT를 검증한다.
4. 앱은 JWT claim의 `sub`를 읽는다.
5. 앱 DB에서 `auth_subject = sub`인 사용자를 찾는다.
6. 없으면 앱 사용자를 생성한다.
7. 앱 내부에서는 `app_users.id`를 기준으로 join 또는 where 조건을 사용한다.

도메인 테이블은 Authentik의 DB PK를 직접 참조하지 않고 앱 내부 PK를 참조한다.

```sql
select p.*
from posts p
join app_users u on p.author_id = u.id
where u.auth_subject = :sub;
```

### Spring 앱 인증 전략

Spring 앱이 이미 존재한다면 JWT 검증만을 위해 `Spring Security OAuth2 Resource Server`를 사용할 수 있다.

Resource Server가 하는 일:

- `Authorization: Bearer <JWT>` 추출
- JWT 서명 검증
- `exp`, `iss`, `aud` 검증
- claim을 `Authentication`으로 변환
- `SecurityContext`에 현재 사용자 저장

Resource Server가 하지 않는 일:

- 로그인 화면 제공
- 회원가입 처리
- 비밀번호 검증
- 세션 로그인
- 토큰 발급

Spring Security 설정 예시:

```java
@Bean
SecurityFilterChain security(HttpSecurity http) throws Exception {
    return http
        .cors(cors -> {})
        .csrf(csrf -> csrf.disable())
        .sessionManagement(session ->
            session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
        )
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/public/**").permitAll()
            .requestMatchers("/admin/**").hasAuthority("ROLE_ADMIN")
            .anyRequest().authenticated()
        )
        .oauth2ResourceServer(oauth -> oauth.jwt())
        .build();
}
```

JWT Bearer API에서는 일반적으로 CSRF를 비활성화한다. 브라우저가 `Authorization` header를 자동으로 붙이지 않기 때문이다. 단, 인증 정보를 cookie로 운용하면 CSRF 방어가 필요하다.

### CORS와 CSRF 기준

| 항목 | 의미 | 처리 위치 |
|---|---|---|
| CORS | 다른 origin의 브라우저 요청 허용 정책 | Spring 또는 reverse proxy |
| CSRF | cookie/session 인증을 악용한 요청 방어 | Spring Security |

권장 기준:

- SPA + Bearer JWT: Spring에서 CORS 설정, CSRF 비활성화
- session/cookie 로그인: CSRF 활성화
- 여러 앱이 각자 origin 정책을 가진 경우: 앱별 Spring CORS 설정
- 공통 정책만 필요한 경우: reverse proxy CORS 설정 가능

### GitHub Actions 배포 전략

인프라 repository도 GitHub Actions로 배포할 수 있다.

기본 흐름:

```txt
push to infra repo
-> GitHub Actions
-> SSH to VPS
-> git pull
-> docker compose config
-> docker compose pull
-> docker compose up -d
```

`docker compose up -d`는 보통 변경된 서비스만 재생성한다. 이미 실행 중인 앱이 있어도 compose project와 network 구성이 안정적이면 전체 앱이 매번 중단되지는 않는다.

주의할 변경:

- Docker network 이름 변경
- compose project name 변경
- volume 이름 변경
- `80/443` port 변경
- Authentik session secret 변경
- DB volume 경로 변경
- `--remove-orphans` 사용

이런 변경은 실행 중인 앱 라우팅, 로그인 세션, 데이터 경로에 영향을 줄 수 있다.

### 배포 명령 기준

초기 수동 배포:

```bash
git pull
docker compose config
docker compose pull
docker compose up -d
```

정리 작업:

```bash
docker image prune -f
```

`--remove-orphans`는 compose 파일에서 제거된 서비스를 중지할 수 있으므로, 앱 compose와 infra compose가 섞여 있을 때는 신중하게 사용한다.

### 운영 원칙

- VPS에서 직접 파일을 수정하지 않는다.
- 변경은 local 또는 GitHub에서 commit으로 관리한다.
- VPS는 repository를 pull해서 반영한다.
- reverse proxy만 public port를 가진다.
- 앱 컨테이너 port는 외부에 publish하지 않는다.
- Authentik DB는 앱에서 직접 조회하지 않는다.
- 앱은 JWT claim의 `sub`를 기준으로 자기 DB의 사용자와 매핑한다.
- 앱 내부 권한은 앱 DB에서 관리한다.
- 공통 인증은 SSO가 담당하고, 도메인 권한은 앱이 담당한다.

## 최종 요약

하나의 VPS에서 여러 앱을 운영할 때는 공통 인프라를 앱 코드와 분리해 `vps-infra` 같은 별도 repository로 관리하는 것이 좋다. Reverse proxy와 SSO는 공통 진입점과 인증을 담당하고, 각 앱은 JWT claim의 `sub`를 자기 DB의 사용자와 매핑해 도메인 권한을 처리한다. Authentik 같은 IdP의 DB는 인증 서버 내부 상태이므로 앱이 직접 접근하지 않는다. 배포는 GitHub Actions로 자동화할 수 있지만, network, volume, secret, port 변경은 실행 중인 앱 전체에 영향을 줄 수 있으므로 별도 검토가 필요하다.
