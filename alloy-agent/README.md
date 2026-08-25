# alloy-agent

An Alloy agent for the **terraform** box. Everything else in this repo is
Terraform that manages containers on **jackserver**; this one is a compose file
because the terraform box is not managed by that Terraform.

It does two things on the box it runs on:

- tails every container's logs (atlantis, the website, its Postgres) and pushes
  them to the central Alloy on jackserver
- accepts OTLP from local apps at `http://alloy:4318` and forwards traces and
  metrics to jackserver

Both connections cross the tailnet, which WireGuard already encrypts, and land
on ports that jackserver publishes only on its Tailscale interface.

## Deploy

```sh
cd ~/repos/convex-infra/alloy-agent
CENTRAL_HOST=<jackserver tailnet address> docker compose up -d
```

## Sending telemetry from an app on this box

Join the network the agent creates and point the OTLP exporter at it:

```yaml
services:
  your-app:
    environment:
      OTEL_SERVICE_NAME: your-app
      OTEL_EXPORTER_OTLP_ENDPOINT: http://alloy:4318
    networks:
      - default
      - observability

networks:
  observability:
    external: true
```

Logs need no configuration — anything the container writes to stdout is picked
up automatically.
