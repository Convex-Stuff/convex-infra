terraform {
    required_providers {
      docker = {
        source = "kreuzwerker/docker"
        version = "4.4.0"
      }
    }
}

provider "docker" {
  host     = "ssh://${var.SERVER_USER}@${var.SERVER_HOST}"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}