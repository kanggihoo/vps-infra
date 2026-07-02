# Portal Services Skills MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small `portal` service that serves a React UI for Services and Skills behind Traefik.

**Architecture:** One Go `net/http` server serves the Vite React build, config JSON, and curated skill markdown files. Traefik routes `portal.kkh-hub.tech` to the Go service. No status collection, DB, or runtime host directory scanning.

**Tech Stack:** Go stdlib, Vite, React, TypeScript, Docker Compose, Traefik.

---

### Task 1: Go Static Server

**Files:**
- Create: `portal/go.mod`
- Create: `portal/cmd/portal/main.go`
- Create: `portal/cmd/portal/main_test.go`

- [x] Write failing tests for SPA fallback and dotfile blocking.
- [x] Run `rtk proxy go test ./...` in `portal` and verify failure.
- [x] Implement minimal Go static server.
- [x] Run `rtk proxy go test ./...` in `portal` and verify pass.

### Task 2: React UI And Static Data

**Files:**
- Create: `portal/package.json`
- Create: `portal/package-lock.json`
- Create: `portal/index.html`
- Create: `portal/tsconfig.json`
- Create: `portal/vite.config.ts`
- Create: `portal/src/main.tsx`
- Create: `portal/src/App.tsx`
- Create: `portal/src/styles.css`
- Create: `portal/public/config/services.json`
- Create: `portal/public/skills/index.json`
- Create: `portal/public/skills/*.md`

- [x] Add Vite React app.
- [x] Render Services and Skills tabs.
- [x] Parse skill frontmatter client-side.
- [x] Render markdown body with a small local parser.
- [x] Add copy buttons for original, body, and install command.
- [x] Run `rtk npm run build`.

### Task 3: Compose Wiring

**Files:**
- Create: `portal/Dockerfile`
- Modify: `compose.yml`
- Modify: `scripts/deploy.sh`

- [x] Add multi-stage Dockerfile.
- [x] Add `portal` service on `proxy` network with Basic Auth middleware.
- [x] Update deploy script to build local services.
- [x] Run `rtk docker compose config`.

### Task 4: Documentation And Verification

**Files:**
- Modify: `.okf/services/index.md`
- Create: `.okf/services/portal.md`
- Modify: `.okf/log.md`

- [x] Add OKF service concept.
- [x] Run strict OKF validation.
- [x] Run full verification commands.
- [x] Commit implementation.
