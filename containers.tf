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

  upload {
    content = file("${path.module}/configs/grafana-datasources.yml")
    file    = "/etc/grafana/provisioning/datasources/datasources.yml"
  }

  upload {
    content = file("${path.module}/configs/grafana-dashboards.yml")
    file    = "/etc/grafana/provisioning/dashboards/dashboards.yml"
  }

  # Mirrors configs/dashboards/<folder>/<name>.json into the container; each
  # subdirectory shows up in Grafana as a folder of that name.
  dynamic "upload" {
    for_each = fileset("${path.module}/configs/dashboards", "**/*.json")

    content {
      content = file("${path.module}/configs/dashboards/${upload.value}")
      file    = "/etc/grafana/dashboards/${upload.value}"
    }
  }

  networks_advanced {
    name = docker_network.observability.name
  }

  env = [
    "GF_SECURITY_ADMIN_USER=${var.GF_SECURITY_ADMIN_USER}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.GF_SECURITY_ADMIN_PASSWORD}",
  ]

  restart = "unless-stopped"
}

resource "docker_container" "loki" {
  name  = "loki"
  image = docker_image.loki.image_id

  command = ["-config.file=/etc/loki/loki.yml"]

  volumes {
    volume_name    = docker_volume.loki_data.name
    container_path = "/loki"
  }

  upload {
    content = file("${path.module}/configs/loki.yml")
    file    = "/etc/loki/loki.yml"
  }

  networks_advanced {
    name = docker_network.observability.name
  }

  restart = "unless-stopped"
}

resource "docker_container" "prometheus" {
  name  = "prometheus"
  image = docker_image.prometheus.image_id

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=30d",
    # Unlike loki and tempo, prometheus can cap by size. Whichever limit is
    # reached first wins, so a metrics flood cannot outgrow the disk.
    "--storage.tsdb.retention.size=10GB",
    "--web.enable-remote-write-receiver",
  ]

  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  upload {
    content = file("${path.module}/configs/prometheus.yml")
    file    = "/etc/prometheus/prometheus.yml"
  }

  networks_advanced {
    name = docker_network.observability.name
  }

  restart = "unless-stopped"
}

resource "docker_container" "tempo" {
  name  = "tempo"
  image = docker_image.tempo.image_id

  command = ["-config.file=/etc/tempo/tempo.yml"]

  volumes {
    volume_name    = docker_volume.tempo_data.name
    container_path = "/var/tempo"
  }

  upload {
    content = file("${path.module}/configs/tempo.yml")
    file    = "/etc/tempo/tempo.yml"
  }

  networks_advanced {
    name = docker_network.observability.name
  }

  restart = "unless-stopped"
}

resource "docker_container" "alloy" {
  name  = "alloy"
  image = docker_image.alloy.image_id

  volumes {
    volume_name    = docker_volume.alloy_data.name
    container_path = "/var/lib/alloy/data"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  upload {
    content = file("${path.module}/configs/alloy.alloy")
    file    = "/etc/alloy/config.alloy"
  }

  # Ingestion from other boxes on the tailnet (currently the alloy agent on the
  # terraform box). Bound to the Tailscale address rather than 0.0.0.0, since
  # published Docker ports bypass the host firewall.
  ports {
    internal = 4317
    external = 4317
    ip       = var.TAILNET_IP
  }

  ports {
    internal = 3101
    external = 3101
    ip       = var.TAILNET_IP
  }

  networks_advanced {
    name = docker_network.observability.name
  }

  restart = "unless-stopped"
}
