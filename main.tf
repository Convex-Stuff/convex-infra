terraform {
    required_providers {
      docker = {
        source = "kreuzwerker/docker"
        version = "4.4.0"
      }
    }
}

provider "docker" {
  host     = "ssh://${var.SERVER_USER}@${var.SERVER_HOST}:23"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_volume" "grafana_data" {
  name = "grafana-data"
}

resource "docker_container" "grafana" {
  name  = "grafana"
  image = docker_image.grafana.image_id

  ports {
    internal = 3000
    external = 3001
  }

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  env = [
    "GF_SECURITY_ADMIN_USER=${var.GF_SECURITY_ADMIN_USER}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.GF_SECURITY_ADMIN_PASSWORD}",
  ]

  restart = "unless-stopped"
}