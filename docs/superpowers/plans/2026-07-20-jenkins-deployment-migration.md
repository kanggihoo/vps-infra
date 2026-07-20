# Jenkins Deployment Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move VPS infrastructure deployment trigger from GitHub Actions to a Jenkins container running on the same VPS.

**Architecture:** Jenkins runs as a separate Compose project behind Traefik. Jenkins checks out the repository into the existing `/opt/vps-infra` deployment directory, then invokes the existing deployment and health-check scripts through the host Docker socket. GHCR is out of scope; images remain locally built on the VPS.

**Tech Stack:** Jenkins LTS, Docker Compose, Traefik, GitHub webhook, Declarative Jenkins Pipeline, Bash.

## Global Constraints

- Keep public ports limited to `80` and `443`.
- Keep runtime secrets in VPS-only `.env` and `traefik/acme.json`.
- Keep Jenkins in a separate Compose project from the infrastructure stack.
- Prevent concurrent deployments.
- Do not enable GitHub Actions and Jenkins deployment simultaneously.

### Task 1: Jenkins runtime

**Files:**
- Create: `jenkins/Dockerfile`
- Create: `jenkins/compose.yml`
- Create: `jenkins/README.md`

- [ ] Build Jenkins image with Docker CLI and Git.
- [ ] Run Jenkins behind `vps_proxy` without publishing port `8080`.
- [ ] Persist `/var/jenkins_home`.
- [ ] Document one-time host bootstrap and Docker socket security risk.

### Task 2: Pipeline

**Files:**
- Create: `Jenkinsfile`

- [ ] Checkout the repository into `/opt/vps-infra` without deleting `.env` or `traefik/acme.json`.
- [ ] Validate Compose configuration.
- [ ] Select `portal` only when every changed file is under `portal/`; otherwise select `all`.
- [ ] Run `scripts/deploy.sh` and `scripts/healthcheck.sh`.
- [ ] Disable concurrent builds and set a timeout.

### Task 3: Documentation and validation

**Files:**
- Modify: `.github/workflows/deploy.yml`
- Modify: `.okf/index.md`
- Create: `.okf/services/jenkins-deploy.md`
- Modify: `.okf/architecture/system-overview.md`
- Modify: `.okf/services/github-actions-deploy.md`

- [ ] Disable the old deployment workflow to prevent duplicate deploys.
- [ ] Document Jenkins credentials, webhook, DNS, and first-run validation.
- [ ] Run Compose config, shell syntax, and static pipeline checks.
