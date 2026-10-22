# Divertiflix infrastructure

Infrastructure as code for **Divertiflix**, a fictional streaming company (5 employees),
built for the course 420-511-SH (Équipe 1).

- **OpenTofu** creates one Debian 13 VM on a Proxmox VE hypervisor.
- **Ansible** configures that VM and deploys every service in Docker Compose behind **Traefik**.
- An internal certificate authority (**Step CA**) issues the HTTPS certificates.

No real secret is stored in this repository. Passwords and keys live in an encrypted
Ansible vault that is never committed (see [Secrets](#secrets)).

## Architecture

```
 clients ──► Traefik (80/443 on the VM) ──► services (Docker network "proxy")
               ▲                                │
               │ certificates (ACME)            │ names resolved by dnsmasq
            Step CA                             ▼
                                         <name>.home.arpa  →  VM IP
```

- **VM**: created by OpenTofu on Proxmox, system disk `/dev/vda`, media disk `/dev/vdb`
  mounted on `/srv/storage`.
- **Traefik** publishes ports 80 and 443 on the VM and routes `<name>.home.arpa` to each service.
- **Step CA** is the internal CA. Traefik gets its certificates from it through ACME.
- **dnsmasq** (container) answers `<name>.home.arpa` with the VM address. It is generated
  from the `services` map, so adding a service adds its DNS name.
- **Docker network `proxy`**: one bridge network with a fixed IP per service. The range comes from
  the variable `docker_network_prefix` (default `192.168.12`), so it never needs to be
  hard-coded elsewhere.
- **qBittorrent** shares the network of the **Gluetun** container (Mullvad over WireGuard), so
  its traffic always goes through the VPN. Gluetun recreation triggers a qBittorrent restart
  (Ansible handler).

### Services

| Service | Purpose | Role / tag |
|---|---|---|
| dnsmasq | Internal DNS | `dns` |
| Step CA | Internal certificate authority | `small_step` |
| Traefik | Reverse proxy, HTTPS | `traefik` |
| Jellyfin | Media server | `jellyfin` |
| Gluetun + qBittorrent | VPN gateway and torrent client | `gluetun`, `qbittorrent` |
| Prowlarr, FlareSolverr | Indexer manager and its helper | `prowlarr`, `flaresolverr` |
| Sonarr, Radarr, Bazarr | TV, movies, subtitles | `sonarr`, `radarr`, `bazarr` |
| Jellyseerr | Media requests | `jellyseerr` |
| Homarr | Dashboard | `homarr` |
| Immich | Photo library | `immich` |
| Cleanuparr | Download queue cleanup | `cleanuparr` |
| Vaultwarden | Password manager | `vaultwarden` |
| GLPI | IT asset management and helpdesk | `glpi` |
| BookStack | Documentation wiki | `bookstack` |
| ntfy | Notifications | `ntfy` |

Optional roles, commented out in `ansible/playbook.yml`: `nginx`, `xray`, `uptime_kuma`.

Each service is reachable at `<name>.home.arpa` (underscores become dashes).

## Repository layout

```
tofu/proxmox/     OpenTofu: VM, Debian cloud image, cloud-init (bpg/proxmox provider)
ansible/          playbook.yml, one role per service, group_vars/all/vars.yml
cert/             root CA of Step CA, fetched by Ansible (git-ignored except .gitkeep)
Makefile          shortcuts for the checks (make help)
.github/          CI workflow (lint, OpenTofu, secret scan)
.yamllint         YAML style rules
.pre-commit-config.yaml   git hooks (gitleaks)
```

## One-time preparation

### On the Proxmox host

```bash
pveum user add terraform@pve
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt User.Modify"
pveum aclmod / -user terraform@pve -role Terraform
pveum user token add terraform@pve provider --privsep=0
```

Enable the content types `snippets` and `import` on the datastore used for them.
(`VM.Monitor` does not exist on PVE 9, so it is not in the list.)

### On the jump host

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
ssh-copy-id -i ~/.ssh/id_rsa root@<proxmox-ip>
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_rsa
export TF_VAR_proxmox_api_token='terraform@pve!provider=<secret>'
```

Install OpenTofu, Ansible and the Ansible collections:

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

## Deployment

### 1. Create the VM

```bash
cd tofu/proxmox
cp terraform.tfvars.example terraform.tfvars   # then edit
tofu init
tofu plan -out plan
tofu apply plan
```

### 2. Configure the services

```bash
cd ansible
cp inventory/hosts.yml.example inventory/hosts.yml             # then edit
cp group_vars/all/vault.yml.example group_vars/all/vault.yml   # fill in the values
echo '<vault password>' > ~/.vault_pass_divertiflix && chmod 600 ~/.vault_pass_divertiflix
ansible-vault encrypt group_vars/all/vault.yml
ansible-playbook playbook.yml
# one service only:
ansible-playbook playbook.yml --tags traefik
```

Roles run in dependency order: `mount, docker, dns, small_step, traefik, media_storage`,
then the applications. Traefik depends on Docker, DNS and Step CA, so deploy those first
when you use `--tags`.

### 3. Trust the CA on the clients

The root certificate is fetched to `cert/step_ca_root_ca.crt`. Import it into the browser
or the system certificate store of every client.

### Rebuild from scratch

```bash
tofu -chdir=tofu/proxmox destroy
ssh-keygen -R <vm-ip>
# then repeat steps 1 and 2
```

## Secrets

- Secrets live **only** in `ansible/group_vars/all/vault.yml` (encrypted with `ansible-vault`,
  git-ignored). Only `vault.yml.example`, filled with `CHANGE_ME`, is committed.
- The Proxmox API token is passed through the environment variable `TF_VAR_proxmox_api_token`,
  never in a file.
- Compose templates escape `$` in secrets and roles that handle secrets use file mode `0600`
  and `no_log`.
- Never paste real passwords, tokens or addresses into issues, commits or chats with an AI.

## Conventions

- The domain is the variable `domain` (`home.arpa`): never hard-code it.
- Add a service in `ansible/group_vars/all/vars.yml` (the `services:` and `images:` maps), then
  create `ansible/roles/<name>/` with `tasks/main.yml` and `templates/docker-compose.yml.j2`,
  and add it to `ansible/playbook.yml`. Do not hard-code IPs or image tags in templates.
- Every role has a `docker_compose_v2` start task. Variables registered inside a role start with
  the role name (`dns_`, `docker_`, ...).

## Checks

Run everything with one command before pushing:

```bash
make help    # list the targets
make check   # lint + syntax-check + OpenTofu fmt/validate
```

| Target | What it does |
|---|---|
| `make lint` | yamllint and ansible-lint |
| `make syntax` | `ansible-playbook --syntax-check` with the example inventory |
| `make tofu-fmt` | checks OpenTofu formatting |
| `make tofu-validate` | `tofu init -backend=false` then `tofu validate` (needs internet) |
| `make hooks` | installs the git pre-commit hook (gitleaks) |

Needs `yamllint`, `ansible-lint` and the `ansible` package (it includes the collections used by
the roles). The same targets run in GitHub Actions on every push and pull request, plus a
gitleaks scan of the full history. Run `make hooks` once per clone so secrets are blocked
before they are committed.

## Troubleshooting

- **Certificate not issued**: check that the service name resolves through the dns container
  (`docker exec dns cat /etc/dnsmasq.conf`), then reset ACME:
  ```bash
  #cert dont work? look the dns 
  cd /srv/docker/dns
  sudo docker compose restart
  cd ~
  sudo docker exec dns cat /etc/dnsmasq.conf
  sudo docker stop traefik
  sudo rm /srv/docker/traefik/acme.json
  sudo touch /srv/docker/traefik/acme.json
  sudo chmod 600 /srv/docker/traefik/acme.json
  sudo docker start traefik
  ```
- **qBittorrent has no network after a Gluetun restart**: `docker restart qbittorrent`
  (Ansible does this automatically when it recreates Gluetun).
- **`The vault password file ... was not found`**: create `~/.vault_pass_divertiflix`
  (step 2), or use `make lint syntax`, which falls back to a dummy file.
- **First login**: BookStack uses `admin@admin.com` / `password` (change it immediately);
  qBittorrent prints a temporary password in `docker logs qbittorrent`.

## Known limitations

- Most image tags are still `latest` (only Traefik is pinned): pin them before a demo.
- Traefik reads the Docker socket directly (read-only mount): a socket-proxy is planned.
- `proxmox_insecure` defaults to `true`: use a valid certificate on Proxmox and set it to `false`.
- Backups (Proxmox Backup Server to the NAS) are not part of this repository yet.
- Vaultwarden signups are open until the first accounts exist
  (`vaultwarden_signups_allowed`).