output "instance_name" {
  value = google_compute_instance.ubuntu_vm.name
}

output "external_ip" {
  value = google_compute_instance.ubuntu_vm.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  value = "ssh ${var.ssh_user}@${google_compute_instance.ubuntu_vm.network_interface[0].access_config[0].nat_ip}"
}
