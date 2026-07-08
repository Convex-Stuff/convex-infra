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