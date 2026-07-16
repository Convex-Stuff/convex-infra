resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_image" "loki" {
  name         = "grafana/loki:3.7.3"
  keep_locally = true
}

resource "docker_image" "alloy" {
  name         = "grafana/alloy:v1.17.1"
  keep_locally = true
}