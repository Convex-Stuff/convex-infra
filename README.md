# convex-infra

Contains terraform for infrastructure required for my apps.

## Telemetry agents

The Terraform here manages the central Grafana stack on **jackserver**,
including the Alloy that receives logs on `:3101` and OTLP on `:4317` over the
tailnet.

Boxes other than jackserver run their own Alloy agent alongside the app they
collect for, forwarding to jackserver. The **terraform** box's agent lives in
the `united-states-suiji` repo (`alloy/config.alloy` plus the `alloy` service in
`docker-compose.prod.yml`) and is deployed by that repo's workflow.

Do not add a second agent for a box that already has one - two agents tailing
the same Docker socket ship every container's logs twice.
