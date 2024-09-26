provider "google" {
  project = "mcgill-fiam-154324"
  region  = "us-central1"
}

# Define a firewall rule to allow access from any IP address to port 8888
resource "google_compute_firewall" "allow_jupyter" {
  name    = "allow-jupyter-access"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  source_ranges = ["0.0.0.0/0"]  # WARNING: Opens the port to everyone; secure it properly in production environments
}

# List of zones with available NVIDIA T4 GPUs to try
variable "zones" {
  default = [
    "us-central1-a",
    "us-central1-b",
    "us-central1-c",
    "us-west1-a",
    "us-west1-b",
    "us-west1-c",
    "europe-west1-b",
    "asia-east1-a"
  ]
}

# Create the VM instance, iterating over the list of zones
resource "google_compute_instance" "training_vm" {
  for_each = toset(var.zones)
  name     = "training-vm-instance"
  zone     = each.key
  machine_type = "n1-standard-4"

  guest_accelerator {
    type  = "nvidia-tesla-t4"
    count = 1
  }

  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"
      size  = 40
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y nvidia-driver-470 nvidia-cuda-toolkit
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker $USER
    docker pull pytorch/pytorch:2.0.1-cuda11.7-cudnn8-runtime
    docker run --gpus all -it -d -p 8888:8888 --name pytorch-jupyter pytorch/pytorch:2.0.1-cuda11.7-cudnn8-runtime
  EOT

  # Optional provisioner to log which instance was created
  provisioner "local-exec" {
    command    = "echo ${self.name} created in ${self.zone}"
    when       = create
    on_failure = continue
  }
}

# Output the zone of the first created instance
output "selected_zone" {
  value = values(google_compute_instance.training_vm)[0].zone
}