terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_compute_instance" "ubuntu_vm" {
  name         = "adbc-patchtester"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2604-lts-amd64"
      size  = 20
      type  = "hyperdisk-balanced"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnet

    access_config {
      # Ephemeral public IP for SSH access
    }
  }

  metadata = {
    user-data = file("${path.module}/cloud-init.yaml")
    ssh-keys  = "${var.ssh_user}:${file(var.ssh_public_key_file)}"
  }

  tags = ["allow-ssh"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
}
