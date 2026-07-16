resource "docker_volume" "grafana_data" {
  name = "grafana-data"
}

resource "docker_volume" "loki_data" {
  name = "loki-data"
}

resource "docker_volume" "alloy_data" {
  name = "alloy-data"
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus-data"
}