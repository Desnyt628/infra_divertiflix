output "vm_id" {
  value = proxmox_virtual_environment_vm.docker_host.vm_id
}

output "vm_ipv4_address" {
  value = var.vm_ipv4_address
}

output "ssh_command" {
  value = "ssh ${var.vm_admin_user}@${split("/", var.vm_ipv4_address)[0]}"
}
