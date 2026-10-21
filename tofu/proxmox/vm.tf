resource "proxmox_virtual_environment_vm" "docker_host" {
  name            = var.vm_name
  node_name       = var.proxmox_node
  vm_id           = var.vm_id
  description     = "Managed by OpenTofu"
  tags            = ["tofu", "docker"]
  stop_on_destroy = false

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cores
  }

  memory {
    dedicated = var.vm_memory
    floating  = var.vm_memory_floating
  }

  initialization {
    datastore_id = var.datastore_vm

    dns {
      domain  = var.domain
      servers = var.vm_dns_servers
    }

    ip_config {
      ipv4 {
        address = var.vm_ipv4_address
        gateway = var.vm_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  # System disk (/dev/vda)
  disk {
    datastore_id = var.datastore_vm
    import_from  = proxmox_virtual_environment_download_file.debian_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.vm_os_disk_gb
  }

  # Media disk (/dev/vdb, mounted on /srv/storage by the mount role)
  disk {
    datastore_id = var.datastore_vm
    interface    = "virtio1"
    iothread     = true
    discard      = "on"
    size         = var.vm_media_disk_gb
  }

  network_device {
    bridge  = var.vm_bridge
    vlan_id = var.vm_vlan_id
  }

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}
