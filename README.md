# Divertiflix infrastructure

OpenTofu creates the Docker VM on Proxmox, Ansible deploys the services on it.
No real secret is stored in this repo: see `ansible/group_vars/all/vault.yml.example`.

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
Install OpenTofu, Ansible and the collections:
```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

## 1. Create the VM
```bash
cd tofu/proxmox
cp terraform.tfvars.example terraform.tfvars   # then edit
tofu init
tofu plan -out plan
tofu apply plan
```

## 2. Configure the services
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
Deploy order follows the dependencies:
`mount, docker, dns, small_step, traefik`, then the applications.

## 3. Trust the CA on the clients
The root certificate is fetched to `cert/step_ca_root_ca.crt`.
Import it into the browser or the system store.

## Rebuild from scratch
```bash
tofu -chdir=tofu/proxmox destroy
ssh-keygen -R <vm-ip>
# then repeat steps 1 and 2
```

## Troubleshooting
- Certificate not issued: check that the service name resolves through the dns container
  (`docker exec dns cat /etc/dnsmasq.conf`), then reset ACME:
  ```bash
  docker stop traefik
  : > /srv/docker/traefik/acme.json && chmod 600 /srv/docker/traefik/acme.json
  docker start traefik
  ```
- qBittorrent has no network after a gluetun restart: `docker restart qbittorrent`.
- First login: BookStack uses `admin@admin.com` / `password` (change it immediately),
  qBittorrent prints a temporary password in `docker logs qbittorrent`.
