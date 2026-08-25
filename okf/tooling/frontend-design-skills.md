---
type: Tooling
title: Frontend Design Skills
description: 이 repository의 portal과 frontend 작업을 위해 project scope로 설치된 Codex frontend design skill set.
tags: [agents, frontend, design, codex, skills, tooling]
timestamp: 2026-08-25T00:00:00+09:00
---

# 개요

Frontend Design Skills는 runtime service가 아니라 이 repository의 `portal/` React UI와
frontend 작업을 지원하는 project-scoped Codex skill set이다.

# 설치 범위

- agent: `codex`
- scope: project
- 위치: `.agents/skills/`
- lock file: `skills-lock.json`

# 현재 포함된 frontend 관련 skill

- `brandkit`
- `design-md`
- `design-taste-frontend`
- `frontend-design`
- `high-end-visual-design`
- `image-to-code`
- `imagegen-frontend-mobile`
- `imagegen-frontend-web`
- `industrial-brutalist-ui`
- `minimalist-ui`
- `redesign-existing-projects`
- `shadcn`
- `stitch-design-taste`
- `theme-factory`
- `vercel-composition-patterns`
- `vercel-react-best-practices`
- `web-artifacts-builder`
- `web-design-guidelines`

실제 설치 목록은 `.agents/skills/`를 기준으로 하며, source repository의 원래 skill
이름과 project 디렉터리 이름이 다를 수 있다. 정확한 source와 hash는
`skills-lock.json`을 기준으로 한다.

# 사용 원칙

- [공용 인프라 포털](/services/portal.md) UI 작업 시 frontend/design skill을 우선 사용한다.
- shadcn/ui 프로젝트에서는 `components.json`과 `globals.css`를 먼저 확인한다.
- DESIGN.md를 만들거나 수정할 때는 repository에 존재하는 관련 design 문서를 먼저 확인한다.

# 관련 개념

- [공용 인프라 포털](/services/portal.md)
