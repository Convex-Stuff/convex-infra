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

## Reverse proxy

`caddy/` is the reverse proxy for every site on the **terraform** box,
deployed by `.github/workflows/deploy-caddy.yml` on changes to it. Only one
container can hold ports 80 and 443, so this Caddy serves them all; each site
is its own compose stack, deployed from its own repo, that joins `edge`, a
Docker network external to every project.

Every site is proxied by Cloudflare and presents a Cloudflare Origin
Certificate, one per zone, stored as `<SITE>_ORIGIN_CERT` / `<SITE>_ORIGIN_KEY`
in this repo's secrets. None can use ACME: the challenge cannot complete
through a proxy that terminates TLS at the edge.

To add a site:

1. In the site's compose file, join its web container to the external `edge`
   network under a name unique on that network.
2. Add a block for it to `caddy/site/Caddyfile`, proxying to that name.
3. Add its origin certificate as two secrets, and write them to `certs/` in
   the deploy script alongside the others, including the empty-value check.

The Caddyfile is mounted by its directory, never as a single file. A file bind
mount pins the container to one inode, so a deploy replacing the file leaves
the container reading the original, and reloads silently re-apply it.
