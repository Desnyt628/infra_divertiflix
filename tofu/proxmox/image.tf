resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  content_type       = "import"
  datastore_id       = var.datastore_images
  node_name          = var.proxmox_node
  url                = var.debian_image_url
  file_name          = "debian-13-cloud-amd64.qcow2"
  checksum           = var.debian_image_checksum
  checksum_algorithm = "sha512"
}
