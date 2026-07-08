resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}