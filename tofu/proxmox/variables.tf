# ---------- Proxmox access ----------
variable "proxmox_api_endpoint" {
  type        = string
  description = "Proxmox API endpoint, e.g. https://192.168.0.2:8006"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "API token in the form user@realm!tokenid=secret (pass it with TF_VAR_proxmox_api_token)"
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Skip TLS verification (self-signed certificate)"
}

variable "proxmox_ssh_user" {
  type    = string
  default = "root"
}

variable "proxmox_node" {
  type    = string
  default = "proxmax"
}

# ---------- Datastores ----------
variable "datastore_images" {
  type        = string
  default     = "local"
  description = "Datastore with the 'import' content type enabled"
}

variable "datastore_snippets" {
  type        = string
  default     = "local"
  description = "Datastore with the 'snippets' content type enabled"
}

variable "datastore_vm" {
  type        = string
  default     = "local-lvm"
  description = "Datastore for the VM disks and the cloud-init drive"
}

# ---------- Debian cloud image ----------
variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/trixie/20251117-2299/debian-13-generic-amd64-20251117-2299.qcow2"
}

variable "debian_image_checksum" {
  type    = string
  default = "1882f2d0debfb52254db1b0fc850d222fa68470a644a914d181f744ac1511a6caa1835368362db6dee88504a13c726b3ee9de0e43648353f62e90e075f497026"
}

# ---------- VM ----------
variable "vm_id" {
  type    = number
  default = 1001
}

variable "vm_name" {
  type    = string
  default = "docker-host"
}

variable "vm_cores" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type        = number
  default     = 16384
  description = "Dedicated memory in MB"
}

variable "vm_memory_floating" {
  type        = number
  default     = 8192
  description = "Minimum (ballooning) memory in MB"
}

variable "vm_os_disk_gb" {
  type    = number
  default = 20
}

variable "vm_media_disk_gb" {
  type        = number
  default     = 500
  description = "Second disk, mounted on /srv/storage (must match storage_device in Ansible: /dev/vdb)"
}

# ---------- VM network ----------
variable "vm_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vm_vlan_id" {
  type        = number
  default     = null
  description = "VLAN tag, null for none"
}

variable "vm_ipv4_address" {
  type        = string
  default     = "192.168.8.240/24"
  description = "Must match docker_host_ip in ansible/group_vars/all/vars.yml"
}

variable "vm_gateway" {
  type    = string
  default = "192.168.8.1"
}



variable "vm_dns_servers" {
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
  description = "DNS servers given to the VM by cloud-init, until the dns role takes over. Set them in terraform.tfvars (for example a local resolver)."
}



variable "domain" {
  type    = string
  default = "home.arpa"
}

# ---------- Access to the VM ----------
variable "vm_admin_user" {
  type    = string
  default = "debian"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "timezone" {
  type    = string
  default = "America/Toronto"
}
