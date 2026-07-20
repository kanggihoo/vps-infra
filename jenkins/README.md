# Jenkins

Jenkins runs as a separate Compose project. It shares the existing `vps_proxy`
network and routes through Traefik at `https://jenkins.kkh-hub.tech`.

## One-time VPS setup

Run as an administrator on the VPS:

```bash
cd /opt/vps-infra
sudo mkdir -p /opt/jenkins
sudo cp jenkins/.env.example /opt/jenkins/.env
sudo sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" /opt/jenkins/.env
sudo chown -R 1000:1000 /opt/jenkins
cd /opt/vps-infra/jenkins
sudo docker compose --env-file /opt/jenkins/.env up -d --build
sudo docker logs vps-jenkins
```

The host must already have Docker, the `vps_proxy` network, and the
`/opt/vps-infra` deployment checkout. Jenkins needs write access to that
checkout so its Pipeline can update it without deleting `.env` or
`traefik/acme.json`.

## Jenkins setup

1. Open `https://jenkins.kkh-hub.tech`.
2. Create one administrator account.
3. Disable anonymous read access and user signup.
4. Add GitHub checkout credentials.
5. Create a Pipeline job pointing at this repository and `Jenkinsfile`.
6. Configure the GitHub webhook to call the Jenkins GitHub hook endpoint.

The container has access to `/var/run/docker.sock` so the Pipeline can build
and deploy the local Compose stack. This grants Jenkins control over the host
Docker daemon and is equivalent to high host privileges. Keep Jenkins private,
use strong credentials, and restrict who can edit jobs.
