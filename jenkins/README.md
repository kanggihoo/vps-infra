# Jenkins

Jenkins runs as a separate Compose project. It shares the existing `vps_proxy`
network and routes through nginx at `https://jenkins.kkh-hub.tech`.

## One-time VPS setup

Run as the deploy user (`kkh`) on the VPS. No `sudo` is needed.

```bash
git clone https://github.com/kanggihoo/vps-infra.git ~/app/vps-infra
cd ~/app/vps-infra/jenkins
cp .env.example .env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" .env
# Fill in the admin password, PAT, VPS paths, and the age key:
#   SOPS_AGE_KEY_CONTENT=$(base64 < ~/.config/sops/age/keys.txt | tr -d '\n')
docker compose --env-file .env up -d --build
docker logs vps-jenkins
```

`jenkins/.env` is ignored by Git and holds Jenkins' own secrets. `APP_DIR` and
`APP_DIR_HOST` must both be `/home/kkh/app/vps-infra`.

The host must already have Docker and the `vps_proxy` network.

## Updating Jenkins itself

`jenkins/casc/` is bind-mounted into the container. The vps-infra Pipeline
runs `git pull` and then reloads JCasC, so changes to `casc/jenkins.yaml` or
`casc/jobs.groovy` (including new Jobs) apply on push without a rebuild.

The Pipeline never recreates Jenkins (ADR 0007). After changing `plugins.txt`,
`Dockerfile`, `compose.yml`, or `jenkins/.env`, apply it over SSH:

```bash
cd ~/app/vps-infra/jenkins
docker compose --env-file .env up -d --build
```

## Configuration

Users, credentials (`github-pat`, `sops-age-key`), and Jobs are created at
startup and on every reload from `casc/jenkins.yaml` (JCasC) and
`casc/jobs.groovy` (job-dsl). Changes made in the GUI are lost on the next
reload or restart.

The container has access to `/var/run/docker.sock` so the Pipeline can build
and deploy the local Compose stack. This grants Jenkins control over the host
Docker daemon and is equivalent to high host privileges. Keep Jenkins private,
use strong credentials, and restrict who can edit jobs.

The Pipeline runs health checks through the `vps_proxy` Docker network. This
avoids VPS hairpin routing when Jenkins calls the public nginx hostnames.
