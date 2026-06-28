# VPS Infra GitHub Actions Deployment Design

## Purpose

Build a small, Docker-based infrastructure repository for one Hostinger VPS.
The first phase verifies deployment automation and core infrastructure only:
Traefik reverse proxy, PostgreSQL, Redis, and a lightweight HTTP health target.

SSO, app onboarding, monitoring, and backup automation are later phases.

## Scope

### In Scope

- GitHub Actions deployment on `main` push.
- SSH-based deployment to the Hostinger VPS.
- VPS-local repository checkout at `/opt/vps-infra`.
- Docker Compose based runtime.
- Traefik as the only public HTTP/HTTPS entrypoint.
- Let's Encrypt HTTP-01 TLS certificates.
- Traefik dashboard behind Basic Auth.
- `whoami` test service routed through Traefik.
- One PostgreSQL container, not publicly exposed.
- One Redis container, not publicly exposed.
- Docker restart policy for VPS reboot recovery.

### Out of Scope

- SSO/Auth Gateway.
- Application deployment.
- App-specific PostgreSQL database/user creation.
- App-specific Redis ACL user creation.
- Automated backup and restore jobs.
- Monitoring and alerting stack.
- GitHub branch protection rules.

## Architecture

```txt
Internet
  -> DNS
    kkh-hub.tech / traefik.kkh-hub.tech / health.kkh-hub.tech
  -> VPS public IP 187.77.114.68
  -> Traefik :80/:443
  -> Docker internal network
    -> whoami
    -> PostgreSQL
    -> Redis
```

Traefik owns all public HTTP/HTTPS traffic. PostgreSQL and Redis remain internal
to Docker networks and do not publish host ports.

## Repository Layout

Planned layout:

```txt
vps-infra/
  README.md
  compose.yml
  .env.example
  .gitignore
  .github/
    workflows/
      deploy.yml
  traefik/
    traefik.yml
    dynamic.yml
  scripts/
    deploy.sh
    healthcheck.sh
  docs/
    superpowers/
      specs/
        2026-06-28-vps-infra-github-actions-design.md
```

Tracked files define infrastructure behavior. Runtime secrets and generated
state stay on the VPS and are excluded from Git.

## Services

### Traefik

Responsibilities:

- Publish ports `80` and `443`.
- Redirect HTTP to HTTPS.
- Issue Let's Encrypt certificates with HTTP-01.
- Route by hostname.
- Expose dashboard at `traefik.kkh-hub.tech`.
- Protect dashboard with Basic Auth.

Traefik must be the only service publishing public HTTP/HTTPS ports.

### whoami

`traefik/whoami` is the initial end-to-end routing test container.

Route:

```txt
https://health.kkh-hub.tech -> whoami
```

It verifies:

- DNS resolution.
- TLS issuance.
- Traefik routing.
- Docker network connectivity.
- Container response path.

### PostgreSQL

Initial phase:

- Run one PostgreSQL container.
- Use Docker volume persistence.
- Do not publish port `5432`.
- Create only the initial admin/superuser and default database from Docker env.

Future app onboarding:

- Create one database per service.
- Create one database role/user per service.
- Grant each service user access only to its own database.
- Do not let applications use the PostgreSQL superuser.

Recommended future model:

```txt
app1_db + app1_user
app2_db + app2_user
authentik_db + authentik_user
```

Table-prefix-only separation is not accepted as an isolation boundary.

### Redis

Initial phase:

- Run one Redis container.
- Do not publish port `6379`.
- Protect access with password or ACL admin configuration.
- Verify with `PING`.

Future app onboarding:

- Use Redis ACL users per service.
- Use service-specific key prefixes.
- Do not rely on Redis logical database numbers for isolation.

Recommended future model:

```txt
app1_user -> ~app1:* access
app2_user -> ~app2:* access
```

Dangerous commands such as `FLUSHALL`, `FLUSHDB`, `CONFIG`, `KEYS`, `EVAL`,
and `SCRIPT` should be restricted for app-level users.

## DNS And TLS

Hostinger DNS records:

```txt
A      @          187.77.114.68
CNAME  www        kkh-hub.tech
A      traefik    187.77.114.68
A      health     187.77.114.68
```

Resulting hostnames:

```txt
kkh-hub.tech
www.kkh-hub.tech
traefik.kkh-hub.tech
health.kkh-hub.tech
```

TLS policy:

- Use Let's Encrypt HTTP-01.
- Keep VPS and Hostinger firewalls open for `80` and `443`.
- Redirect HTTP to HTTPS.
- Store ACME state on the VPS, not in Git.

## Deployment Flow

Deployment uses GitHub Actions with SSH remote execution.

Trigger:

```yaml
on:
  push:
    branches: [main]
```

Flow:

```txt
main updated
-> GitHub Actions starts
-> SSH to VPS as kkh
-> cd /opt/vps-infra
-> git pull origin main
-> docker compose config
-> docker compose pull
-> docker compose up -d
-> docker compose ps
```

The first version does not include `workflow_dispatch`. Manual workflow
execution can be added later if operations need code-change-free redeploys.

## SSH Deployment Identity

Use the existing VPS user:

```txt
user: kkh
groups: kkh sudo users docker
```

Create a new deploy-only SSH key for GitHub Actions.

Secrets:

```txt
VPS_HOST=187.77.114.68
VPS_USER=kkh
VPS_PORT=22
VPS_SSH_KEY=<deploy-only private key>
```

The public key is registered in:

```txt
/home/kkh/.ssh/authorized_keys
```

The private key is stored only in GitHub Actions repository secrets.

## Runtime Files

Tracked in Git:

- `compose.yml`
- Traefik static/dynamic config.
- GitHub Actions workflow.
- Utility scripts.
- `.env.example`.
- Documentation.

VPS only:

- `.env`
- `traefik/acme.json`
- PostgreSQL volume data.
- Redis volume data.
- Backups.

GitHub Actions must not generate the production `.env`. The VPS keeps runtime
secrets locally.

## Reboot Recovery

The VPS should start Docker on boot:

```bash
sudo systemctl enable docker
```

Compose services should use:

```yaml
restart: unless-stopped
```

After containers are created once by `docker compose up -d`, Docker restarts
them after VPS reboot using stored container metadata and restart policies.

## Validation

Initial deployment is successful when:

1. GitHub Actions succeeds on `main` push.
2. `/opt/vps-infra` is updated to latest `main`.
3. `docker compose config` passes.
4. Traefik, PostgreSQL, Redis, and whoami are running.
5. `https://health.kkh-hub.tech` returns a whoami response.
6. `https://traefik.kkh-hub.tech` requires Basic Auth and shows the dashboard.
7. PostgreSQL passes `pg_isready`.
8. Redis returns `PONG`.
9. Only ports `80` and `443` are publicly reachable.

## Failure Diagnosis Order

Use this order:

```txt
DNS
-> Hostinger/VPS firewall
-> Traefik logs
-> docker compose ps
-> container logs
-> health checks
```

## Later Phases

Planned follow-up work:

1. App onboarding rules.
2. PostgreSQL database/user creation script.
3. Redis ACL user creation rules.
4. Backup and restore automation.
5. Monitoring and logging.
6. Authentik SSO.
7. Branch protection and PR-based deployment policy.
