variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "machine_type" {
  description = "GCP machine type"
  type        = string
}

variable "network" {
  description = "VPC network name or self_link"
  type        = string
}

variable "subnet" {
  description = "Subnetwork name or self_link"
  type        = string
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
}
