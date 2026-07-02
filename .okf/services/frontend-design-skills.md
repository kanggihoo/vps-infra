---
type: Service
title: Frontend Design Skills
description: 이 repository에 project scope로 설치된 Codex frontend design skill set과 DESIGN.md workflow 참고 문서.
tags: [agents, frontend, design, codex, skills]
timestamp: 2026-07-03T00:00:00+09:00
---

# 개요

Frontend Design Skills는 이 repository의 `portal/` React UI와 향후 frontend 작업을 위해
project scope로 설치한 Codex skill set이다.

# 설치 범위

- agent: `codex`
- scope: project
- 위치: `.agents/skills/`
- lock file: `skills-lock.json`

# 포함 skill

- `vercel-react-best-practices`
- `vercel-composition-patterns`
- `deploy-to-vercel`
- `shadcn`
- `taste-skill` set
- `frontend-design`
- `web-artifacts-builder`
- `brand-guidelines`
- `theme-factory`
- `web-design-guidelines`
- `design-md`

# DESIGN.md 참고 문서

DESIGN.md CLI workflow를 위해 다음 문서를 repository에 보관한다.

- `docs/spec.md`
- `docs/shadcn-tailwind-v4.md`
- `docs/shadcn-theming.md`

# 사용 원칙

- [공용 인프라 포털](/services/portal.md) UI 작업 시 frontend/design 관련 skill을 우선 사용한다.
- shadcn/ui 프로젝트에서는 `components.json`과 `globals.css`를 먼저 확인한다.
- DESIGN.md를 만들거나 수정할 때는 `docs/spec.md`를 먼저 읽는다.
- shadcn/ui 호환 CSS가 필요하면 `docs/shadcn-tailwind-v4.md`와 `docs/shadcn-theming.md`를 함께 확인한다.

# 관련 개념

- [공용 인프라 포털](/services/portal.md)
