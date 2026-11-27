## 필수 컨텍스트

- 이 repository는 Hostinger VPS 1대의 공통 인프라를 관리한다.
- 작업 전 `okf/index.md`를 먼저 읽고, 관련 개념 문서를 따라간다.

## 문서 위치

- `okf/`: 지금의 운영 상태(서비스, 아키텍처, 환경, 런북, 트러블슈팅).
- `docs/adr/`: 아키텍처와 운영 결정. 번호를 이어서 쓰고 `docs/adr/index.md`에 추가한다.
- `docs/specs/<slug>/`: 기능별 결정 로그, 스펙, 검증 증거.
## OKF 사용

- 운영 지식은 `okf/`에 한국어로 기록한다. 운영 상태가 바뀌면 해당 문서를 갱신한다.
- OKF concept는 파일 하나당 개념 하나로 유지한다.
- OKF 수정 후 strict validation을 실행한다.

## 변경 규칙

- branch, PR 제목, merge 규칙은 `CONTRIBUTING.md`를 따른다.
