# VPS Infra GitHub Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first deployable Hostinger VPS infrastructure stack with Traefik, PostgreSQL, Redis, whoami, and GitHub Actions SSH deployment.

**Architecture:** GitHub Actions deploys on `main` push by SSH into the VPS as `kkh`, updates `/opt/vps-infra`, and applies Docker Compose. Traefik is the only public entrypoint on `80/443`; PostgreSQL and Redis stay internal and are validated through Compose health checks.

**Tech Stack:** Docker Compose, Traefik, PostgreSQL, Redis, `traefik/whoami`, GitHub Actions, `appleboy/ssh-action`, Bash.

---

## File Structure

Create or update these files:

- `.gitignore`: excludes runtime secrets, ACME state, data volumes, backups, logs, caches, and generated graph output.
- `.env.example`: documents required environment variables without storing production secrets.
- `compose.yml`: defines Traefik, whoami, PostgreSQL, Redis, Docker networks, volumes, labels, and restart policies.
- `traefik/acme.json`: created locally on the VPS only, excluded from Git, chmod `600`.
- `scripts/deploy.sh`: remote deployment script run by GitHub Actions on the VPS.
- `scripts/healthcheck.sh`: local and public validation script.
- `.github/workflows/deploy.yml`: GitHub Actions workflow triggered by `main` push.
- `.okf/runbooks/initial-deployment-validation.md`: update only if validation commands change during implementation.
- `.okf/architecture/system-overview.md`: update only if implemented architecture changes.

Do not commit:

- `.env`
- `traefik/acme.json`
- database data
- Redis data
- backups
- SSH private keys

---

### Task 1: Repository Ignore Rules

**Files:**
- Create or verify: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

Use this exact content:

```gitignore
# Runtime secrets
.env
.env.*
!.env.example

# Traefik / Let's Encrypt state
traefik/acme.json
traefik/acme-staging.json

# Local data and backups
data/
volumes/
backups/
*.dump
*.sql
*.sql.gz
*.rdb
*.aof

# Logs
logs/
*.log

# Tool caches
.cache/
.pytest_cache/
.ruff_cache/
.mypy_cache/
.DS_Store

# Editor / OS
.idea/
.vscode/
*.swp
*.swo

# Graphify generated output
graphify-out/
```

- [ ] **Step 2: Verify ignored secret patterns**

Run:

```bash
git check-ignore .env traefik/acme.json backups/example.sql.gz graphify-out/graph.json
```

Expected output includes:

```txt
.env
traefik/acme.json
backups/example.sql.gz
graphify-out/graph.json
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add infrastructure gitignore"
```

---

### Task 2: Environment Template

**Files:**
- Create: `.env.example`

- [ ] **Step 1: Create `.env.example`**

Use this exact content:

```dotenv
# Traefik
ACME_EMAIL=ops@kkh-hub.tech
TRAEFIK_DASHBOARD_AUTH=admin:example-bcrypt-hash-escaped-for-compose

# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=example-postgres-password
POSTGRES_DB=postgres

# Redis
REDIS_PASSWORD=example-redis-password
```

- [ ] **Step 2: Document VPS `.env` generation commands**

Run these commands on the VPS when preparing `/opt/vps-infra/.env`:

```bash
cd /opt/vps-infra
openssl rand -base64 32
openssl rand -base64 32
```

Use the first generated value for `POSTGRES_PASSWORD` and the second for `REDIS_PASSWORD`.

Generate Traefik Basic Auth on the VPS:

```bash
sudo apt-get update
sudo apt-get install -y apache2-utils
read -r -s -p "Traefik dashboard password: " TRAEFIK_DASHBOARD_PASSWORD
echo
htpasswd -nbB admin "$TRAEFIK_DASHBOARD_PASSWORD" | sed -e 's/\$/\$\$/g'
```

Use the printed `admin:...` value for `TRAEFIK_DASHBOARD_AUTH` in `/opt/vps-infra/.env`.

- [ ] **Step 3: Verify `.env.example` is tracked and `.env` is ignored**

Run:

```bash
git check-ignore .env
git check-ignore .env.example || true
```

Expected:

```txt
.env
```

The second command should print nothing because `.env.example` must be tracked.

- [ ] **Step 4: Commit**

```bash
git add .env.example
git commit -m "chore: add environment template"
```

---

### Task 3: Docker Compose Stack

**Files:**
- Create: `compose.yml`

- [ ] **Step 1: Create `compose.yml`**

Use this exact content:

```yaml
services:
  traefik:
    image: traefik:v3
    container_name: vps-traefik
    restart: unless-stopped
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.letsencrypt.acme.httpchallenge=true
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/acme.json:/letsencrypt/acme.json
    networks:
      - proxy
    labels:
      - traefik.enable=true
      - traefik.http.routers.traefik.rule=Host(`traefik.kkh-hub.tech`)
      - traefik.http.routers.traefik.entrypoints=websecure
      - traefik.http.routers.traefik.tls=true
      - traefik.http.routers.traefik.tls.certresolver=letsencrypt
      - traefik.http.routers.traefik.service=api@internal
      - traefik.http.routers.traefik.middlewares=traefik-auth
      - traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_DASHBOARD_AUTH}

  whoami:
    image: traefik/whoami:v1.10
    container_name: vps-whoami
    restart: unless-stopped
    networks:
      - proxy
    labels:
      - traefik.enable=true
      - traefik.http.routers.health.rule=Host(`health.kkh-hub.tech`)
      - traefik.http.routers.health.entrypoints=websecure
      - traefik.http.routers.health.tls=true
      - traefik.http.routers.health.tls.certresolver=letsencrypt
      - traefik.http.services.health.loadbalancer.server.port=80

  postgres:
    image: postgres:16-alpine
    container_name: vps-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s

  redis:
    image: redis:7-alpine
    container_name: vps-redis
    restart: unless-stopped
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    command: ["sh", "-c", "redis-server --appendonly yes --requirepass \"$${REDIS_PASSWORD}\""]
    volumes:
      - redis-data:/data
    networks:
      - data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$${REDIS_PASSWORD}\" ping | grep PONG"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

networks:
  proxy:
    name: vps_proxy
  data:
    name: vps_data

volumes:
  postgres-data:
    name: vps_postgres_data
  redis-data:
    name: vps_redis_data
```

- [ ] **Step 2: Create local test env from example**

Run locally:

```bash
cp .env.example .env
```

Then edit `.env` locally so `TRAEFIK_DASHBOARD_AUTH`, `POSTGRES_PASSWORD`, and `REDIS_PASSWORD` are non-empty. This `.env` must stay ignored.

- [ ] **Step 3: Validate Compose syntax**

Run:

```bash
docker compose config
```

Expected: rendered Compose config prints without errors.

- [ ] **Step 4: Verify public port policy in rendered config**

Run:

```bash
docker compose config | grep -E 'published: "?(80|443|5432|6379)"?'
```

Expected output includes `80` and `443` only. It must not include `5432` or `6379`.

- [ ] **Step 5: Commit**

```bash
git add compose.yml
git commit -m "feat: add docker compose infrastructure stack"
```

---

### Task 4: Traefik Runtime State Directory

**Files:**
- Create: `traefik/.gitkeep`

- [ ] **Step 1: Create Traefik directory marker**

Create:

```txt
traefik/.gitkeep
```

File content is empty.

- [ ] **Step 2: Create ACME file on VPS**

Run on VPS:

```bash
cd /opt/vps-infra
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json
```

- [ ] **Step 3: Verify ACME state is ignored**

Run locally:

```bash
git check-ignore traefik/acme.json
```

Expected:

```txt
traefik/acme.json
```

- [ ] **Step 4: Commit**

```bash
git add traefik/.gitkeep
git commit -m "chore: add traefik runtime directory"
```

---

### Task 5: Healthcheck Script

**Files:**
- Create: `scripts/healthcheck.sh`

- [ ] **Step 1: Create `scripts/healthcheck.sh`**

Use this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[healthcheck] docker compose config"
docker compose config >/dev/null

echo "[healthcheck] containers"
docker compose ps

echo "[healthcheck] postgres"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[healthcheck] redis"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[healthcheck] public health route"
curl -fsS https://health.kkh-hub.tech >/dev/null

echo "[healthcheck] traefik dashboard auth"
dashboard_status="$(curl -sS -o /dev/null -w "%{http_code}" https://traefik.kkh-hub.tech)"
test "$dashboard_status" = "401"

echo "[healthcheck] ok"
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x scripts/healthcheck.sh
```

- [ ] **Step 3: Run shell syntax check**

Run:

```bash
bash -n scripts/healthcheck.sh
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add scripts/healthcheck.sh
git commit -m "chore: add infrastructure healthcheck script"
```

---

### Task 6: Deploy Script

**Files:**
- Create: `scripts/deploy.sh`

- [ ] **Step 1: Create `scripts/deploy.sh`**

Use this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[deploy] checking required files"
test -f .env
test -f compose.yml
test -f traefik/acme.json

echo "[deploy] validating compose"
docker compose config >/dev/null

echo "[deploy] pulling images"
docker compose pull

echo "[deploy] applying stack"
docker compose up -d

echo "[deploy] compose status"
docker compose ps

echo "[deploy] local postgres check"
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"

echo "[deploy] local redis check"
docker compose exec -T redis redis-cli -a "${REDIS_PASSWORD:?REDIS_PASSWORD is required}" ping | grep -q PONG

echo "[deploy] complete"
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x scripts/deploy.sh
```

- [ ] **Step 3: Run shell syntax check**

Run:

```bash
bash -n scripts/deploy.sh
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add scripts/deploy.sh
git commit -m "chore: add vps deploy script"
```

---

### Task 7: GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Create `.github/workflows/deploy.yml`**

Use this exact content:

```yaml
name: Deploy VPS Infra

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Deploy on VPS
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          port: ${{ secrets.VPS_PORT }}
          script: |
            bash -lc '
              set -euo pipefail
              cd /opt/vps-infra
              git pull --ff-only origin main
              chmod +x scripts/deploy.sh scripts/healthcheck.sh
              ./scripts/deploy.sh
            '
```

- [ ] **Step 2: Verify YAML parses locally**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import yaml
yaml.safe_load(Path(".github/workflows/deploy.yml").read_text())
print("yaml ok")
PY
```

Expected:

```txt
yaml ok
```

If `yaml` is unavailable, run:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path(".github/workflows/deploy.yml").read_text()
for required in ["Deploy VPS Infra", "appleboy/ssh-action@v1.0.0", "git pull --ff-only origin main", "./scripts/deploy.sh"]:
    assert required in text
print("workflow text ok")
PY
```

Expected:

```txt
workflow text ok
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add vps infrastructure deployment workflow"
```

---

### Task 8: VPS Deployment Key Preparation

**Files:**
- No repository file changes.

- [ ] **Step 1: Generate deploy-only key locally**

Run on local machine:

```bash
ssh-keygen -t ed25519 -C "github-actions-vps-infra" -f ~/.ssh/vps_infra_actions
```

Expected files:

```txt
~/.ssh/vps_infra_actions
~/.ssh/vps_infra_actions.pub
```

- [ ] **Step 2: Register public key on VPS**

Run:

```bash
ssh-copy-id -i ~/.ssh/vps_infra_actions.pub kkh@187.77.114.68
```

- [ ] **Step 3: Verify deploy key can connect**

Run:

```bash
ssh -i ~/.ssh/vps_infra_actions -o IdentitiesOnly=yes kkh@187.77.114.68 'whoami && groups'
```

Expected output includes:

```txt
kkh
docker
```

- [ ] **Step 4: Register GitHub Actions secrets**

In GitHub repository settings, add:

```txt
VPS_HOST=187.77.114.68
VPS_USER=kkh
VPS_PORT=22
```

Create `VPS_SSH_KEY` by copying the output of this local command into the GitHub secret value field:

```bash
cat ~/.ssh/vps_infra_actions
```

The private key value is copied into GitHub Secrets only. It is not written into this repository.

---

### Task 9: VPS Initial Directory Setup

**Files:**
- No repository file changes.

- [ ] **Step 1: Enable Docker boot startup**

Run on VPS:

```bash
sudo systemctl enable docker
sudo systemctl status docker --no-pager
```

Expected: Docker service is enabled and active.

- [ ] **Step 2: Prepare repository directory**

Run on VPS:

```bash
sudo mkdir -p /opt/vps-infra
sudo chown -R kkh:kkh /opt/vps-infra
```

- [ ] **Step 3: Clone repository if absent**

Run on VPS with the actual GitHub repository URL:

```bash
if [ ! -d /opt/vps-infra/.git ]; then
  git clone git@github.com:kanggihoo/vps-infra.git /opt/vps-infra
fi
```

- [ ] **Step 4: Verify repository path**

Run on VPS:

```bash
cd /opt/vps-infra
git status --short
git branch --show-current
```

Expected branch:

```txt
main
```

---

### Task 10: VPS Runtime Secret Setup

**Files:**
- Create on VPS only: `/opt/vps-infra/.env`
- Create on VPS only: `/opt/vps-infra/traefik/acme.json`

- [ ] **Step 1: Create `/opt/vps-infra/.env` on VPS**

Run on VPS:

```bash
cd /opt/vps-infra
POSTGRES_PASSWORD_VALUE="$(openssl rand -base64 32)"
REDIS_PASSWORD_VALUE="$(openssl rand -base64 32)"
read -r -s -p "Traefik dashboard password: " TRAEFIK_DASHBOARD_PASSWORD
echo
TRAEFIK_AUTH_VALUE="$(htpasswd -nbB admin "$TRAEFIK_DASHBOARD_PASSWORD" | sed -e 's/\$/\$\$/g')"
cat > .env <<EOF
ACME_EMAIL=ops@kkh-hub.tech
TRAEFIK_DASHBOARD_AUTH=${TRAEFIK_AUTH_VALUE}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD_VALUE}
POSTGRES_DB=postgres
REDIS_PASSWORD=${REDIS_PASSWORD_VALUE}
EOF
chmod 600 .env
```

- [ ] **Step 2: Create ACME file**

Run on VPS:

```bash
cd /opt/vps-infra
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json
```

- [ ] **Step 3: Verify ignored runtime files remain untracked**

Run on VPS:

```bash
cd /opt/vps-infra
git status --short
git check-ignore .env traefik/acme.json
```

Expected output from `git check-ignore`:

```txt
.env
traefik/acme.json
```

---

### Task 11: DNS And Firewall Preparation

**Files:**
- No repository file changes.

- [ ] **Step 1: Configure Hostinger DNS**

Create or verify these records:

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      traefik    187.77.114.68
A      health     187.77.114.68
```

- [ ] **Step 2: Verify local DNS resolution**

Run locally:

```bash
dig +short traefik.kkh-hub.tech
dig +short health.kkh-hub.tech
```

Expected output for both:

```txt
187.77.114.68
```

- [ ] **Step 3: Verify VPS ports**

Run on VPS:

```bash
sudo ss -tulpn | grep -E ':80|:443' || true
```

Before Compose starts, expected output can be empty. After Compose starts, expected owner is Docker proxy or Traefik container.

---

### Task 12: First Manual VPS Deployment

**Files:**
- No repository file changes unless earlier validation reveals a config error.

- [ ] **Step 1: Pull latest repository on VPS**

Run on VPS:

```bash
cd /opt/vps-infra
git pull --ff-only origin main
```

- [ ] **Step 2: Run deploy script**

Run on VPS:

```bash
cd /opt/vps-infra
chmod +x scripts/deploy.sh scripts/healthcheck.sh
./scripts/deploy.sh
```

Expected output includes:

```txt
[deploy] complete
```

- [ ] **Step 3: Verify containers**

Run on VPS:

```bash
cd /opt/vps-infra
docker compose ps
```

Expected services:

```txt
traefik
whoami
postgres
redis
```

- [ ] **Step 4: Verify internal services**

Run on VPS:

```bash
cd /opt/vps-infra
docker compose exec -T postgres pg_isready -U postgres -d postgres
docker compose exec -T redis redis-cli -a "$(grep '^REDIS_PASSWORD=' .env | cut -d= -f2-)" ping
```

Expected:

```txt
accepting connections
PONG
```

---

### Task 13: Public Route Validation

**Files:**
- No repository file changes unless validation reveals a config error.

- [ ] **Step 1: Verify whoami route**

Run locally:

```bash
curl -fsS https://health.kkh-hub.tech
```

Expected output includes request metadata such as:

```txt
Hostname:
IP:
```

- [ ] **Step 2: Verify Traefik dashboard requires auth**

Run locally:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://traefik.kkh-hub.tech
```

Expected:

```txt
401
```

- [ ] **Step 3: Verify Traefik dashboard with credentials**

Run locally:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" -u admin https://traefik.kkh-hub.tech
```

Enter the dashboard password when prompted.

Expected:

```txt
200
```

- [ ] **Step 4: Verify only public HTTP/HTTPS ports are reachable**

Run locally:

```bash
nc -zv 187.77.114.68 80
nc -zv 187.77.114.68 443
nc -zv 187.77.114.68 5432
nc -zv 187.77.114.68 6379
```

Expected:

```txt
80 succeeds
443 succeeds
5432 fails
6379 fails
```

---

### Task 14: GitHub Actions Deployment Validation

**Files:**
- No repository file changes unless workflow validation reveals a config error.

- [ ] **Step 1: Push branch to GitHub**

Run locally:

```bash
git status --short
git push origin main
```

Expected: push succeeds and GitHub Actions starts.

- [ ] **Step 2: Watch workflow**

Use GitHub Actions UI, or run with GitHub CLI if available:

```bash
gh run list --limit 5
gh run watch
```

Expected: `Deploy VPS Infra` succeeds.

- [ ] **Step 3: Verify VPS received latest commit**

Run on VPS:

```bash
cd /opt/vps-infra
git log --oneline -1
docker compose ps
```

Expected: latest commit matches GitHub `main`; all services are running.

---

### Task 15: OKF And Docs Sync

**Files:**
- Modify only if implementation differs from the current knowledge:
  - `.okf/architecture/system-overview.md`
  - `.okf/services/github-actions-deploy.md`
  - `.okf/services/traefik.md`
  - `.okf/services/postgresql.md`
  - `.okf/services/redis.md`
  - `.okf/runbooks/initial-deployment-validation.md`
  - `.okf/log.md`

- [ ] **Step 1: Compare implementation to OKF**

Run:

```bash
grep -R "health.kkh-hub.tech\|traefik.kkh-hub.tech\|vps_data\|vps_proxy" .okf
```

Expected: OKF references match implemented hostnames and network names.

- [ ] **Step 2: Validate OKF if edited**

Run:

```bash
rtk proxy uv run .agents/skills/validate/scripts/okf_validate.py .okf --strict
```

Expected:

```txt
✓ conformant — no issues
```

- [ ] **Step 3: Commit docs sync if edited**

```bash
git add .okf
git commit -m "docs: sync okf with deployed infrastructure"
```

Skip this commit when OKF required no edits.

---

## Self-Review

Spec coverage:

- GitHub Actions `main` push deployment: Task 7 and Task 14.
- SSH deployment to Hostinger VPS as `kkh`: Task 7, Task 8, Task 9.
- VPS-local checkout at `/opt/vps-infra`: Task 9.
- Docker Compose runtime: Task 3, Task 12.
- Traefik public `80/443` entrypoint: Task 3, Task 11, Task 13.
- Let's Encrypt HTTP-01: Task 3, Task 11, Task 13.
- Traefik dashboard Basic Auth: Task 2, Task 3, Task 13.
- whoami health route: Task 3, Task 13.
- PostgreSQL internal only: Task 3, Task 12, Task 13.
- Redis internal only: Task 3, Task 12, Task 13.
- Docker reboot recovery: Task 3 and Task 9.
- Runtime secret exclusion: Task 1, Task 2, Task 10.
- OKF/docs sync: Task 15.

Deferred-marker scan:

- No deferred-marker string or undefined implementation step remains.
- Production secrets are not written into the repository; generation commands are provided.

Type and naming consistency:

- Compose service names are `traefik`, `whoami`, `postgres`, `redis`.
- Container names are `vps-traefik`, `vps-whoami`, `vps-postgres`, `vps-redis`.
- Network names are `vps_proxy` and `vps_data`.
- Volume names are `vps_postgres_data` and `vps_redis_data`.
- Hostnames are `traefik.kkh-hub.tech` and `health.kkh-hub.tech`.
