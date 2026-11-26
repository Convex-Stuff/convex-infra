# convex-infra Specification Sheet

This document is a technical reference for engineers and AI agents working in `convex-infra`. It describes the host topology, services, data flows, configuration contracts, deployment pipelines, and operational invariants of the repository.

---

## 1. Purpose & High-Level Topology

`convex-infra` manages shared infrastructure for apps on the convex network across **two Linux hosts** connected over **Tailscale**:

```text
Internet (Cloudflare Edge TLS, Full Strict)
        │
        ▼  Linode Cloud Firewall (TCP 80/443 restricted to Cloudflare IPv4/IPv6)
┌───────────────────────────────────────────────────────────────────────────┐
│ terraform box (Linode VPS — SSH reachable via Tailscale only)             │
│                                                                           │
│  [Caddy] (caddy/)  ──:80/:443──► external Docker network `edge`           │
│     ├─ uss.convex.coffee  ──► uss-app:3000                                │
│     ├─ lelastechcup.com   ──► ltc-site-web:3000                           │
│     ├─ dans.convex.coffee ──► dans-app:3000                               │
│     └─ bot.convex.coffee  ──► bot:3000                                    │
│                                                                           │
│  [Atlantis] (atlantis/)   ── runs Terraform plans/applies on PRs          │
│  [Remote Alloy]*          ── lives in `united-states-suiji` repo          │
└───────────────────────────┬──────────────────────────┬────────────────────┘
                            │ SSH (Terraform Docker    │ Tailscale (Loki :3101,
                            │ provider)                │ OTLP gRPC :4317)
                            ▼                          ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ jackserver (Central Observability Host — managed by Terraform)            │
│                                                                           │
│  Docker network `observability`:                                          │
│    [Alloy]  ──► [Loki :3100]  [Prometheus :9090]  [Tempo :4317/:3200]     │
│    [Grafana :3000 → host :3001]                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Ownership Boundaries
- **Managed here**:
  - Central observability stack on **jackserver** (via Terraform + Atlantis).
  - Shared Caddy reverse proxy on **terraform box** (via Docker Compose + GitHub Actions).
  - Atlantis server on **terraform box** (via Docker Compose + GitHub Actions).
  - Linode Cloud Firewall Cloudflare-IP sync script (`scripts/update-cloudflare-firewall.ts`).
- **Managed in individual application repos** (NOT here):
  - Application Docker Compose stacks (each joins the external `edge` network on the terraform box).
  - Remote Alloy agents on non-jackserver boxes (e.g., the terraform box's Alloy agent lives in `united-states-suiji` and ships logs/OTLP to jackserver over Tailscale).

---

## 2. Repository Layout

| Path | Role |
| :--- | :--- |
| `providers.tf` | Terraform `kreuzwerker/docker` (`4.4.0`) provider configured over SSH to `SERVER_USER@SERVER_HOST`. |
| `backend.tf` | Local Terraform state backend stored inside the Atlantis volume (`/home/atlantis/.atlantis/tfstate/convex-infra/terraform.tfstate`). |
| `variables.tf` | Terraform input variables (`SERVER_USER`, `SERVER_HOST`, `GF_SECURITY_ADMIN_USER`, `GF_SECURITY_ADMIN_PASSWORD`, `TAILNET_IP` with `100.64.0.0/10` regex validation). |
| `networks.tf` | Defines the `observability` Docker network on jackserver. |
| `volumes.tf` | Defines persistent Docker volumes: `grafana-data`, `loki-data`, `alloy-data`, `prometheus-data`, `tempo-data`. |
| `images.tf` | Pins Docker images for the observability stack (`keep_locally = true`). |
| `containers.tf` | Defines the 5 observability containers, mounts, ports, and `upload` blocks for configs and dashboards. |
| `configs/alloy.alloy` | Central Alloy pipeline: local Docker logs, remote Loki push API, scrubbing, OTLP receiver/scrubbing, Prometheus scraping & remote write. |
| `configs/loki.yml` | Loki v13 TSDB filesystem config, 14-day retention, ingestion/cardinality guardrails. |
| `configs/prometheus.yml` | Minimal Prometheus config (storage + remote-write receiver only; Alloy performs all scraping). |
| `configs/tempo.yml` | Tempo local filesystem trace storage, 14-day retention, ingestion ceilings. |
| `configs/grafana-datasources.yml` | Provisions `loki`, `prometheus` (default), and `tempo` datasources with bidirectional trace ↔ log correlation. |
| `configs/grafana-dashboards.yml` | Provisions file-based dashboards from `/etc/grafana/dashboards` using directory names as Grafana folders. |
| `configs/dashboards/<folder>/*.json` | Version-controlled Grafana dashboards dynamically uploaded by Terraform. |
| `atlantis.yaml` | Repo-level Atlantis config (`convex-infra` project, autoplan triggers, custom `init -reconfigure` workflow). |
| `atlantis/docker-compose.yml` | Atlantis container definition (`network_mode: host`, SSH key mount, `atlantis-data` volume). |
| `atlantis/repos.yaml` | Server-side Atlantis repo config enabling custom workflows. |
| `caddy/docker-compose.yml` | Shared Caddy reverse proxy Compose stack on the terraform box. |
| `caddy/site/Caddyfile` | Virtual hosts, Cloudflare Origin Cert TLS directives, and upstream container reverse proxies. |
| `caddy/.gitignore` | Ignores `caddy/certs/` (populated on deploy from GitHub secrets). |
| `.github/workflows/deploy-atlantis.yml` | Deploys `atlantis/` to the terraform box over Tailscale + SSH on push to `main`. |
| `.github/workflows/deploy-caddy.yml` | Validates and deploys `caddy/` + Origin Certs to the terraform box over Tailscale + SSH on push to `main`. |
| `scripts/update-cloudflare-firewall.ts` | Bun script to restrict Linode Cloud Firewall ports 80/443 to Cloudflare's published IPv4/IPv6 ranges. |
| `scripts/windows-setup.ps1` | Standalone personal Windows Scoop workstation bootstrap script (not part of server infra). |

---

## 3. Central Observability Stack (`jackserver`)

Provisioned declaratively by Terraform using the Docker provider over SSH (`ssh://${var.SERVER_USER}@${var.SERVER_HOST}`). All five containers attach to the `observability` bridge network with `restart = "unless-stopped"`.

### Services & Images

| Container | Image | Volume | Exposed Ports | Retention / Limits |
| :--- | :--- | :--- | :--- | :--- |
| `grafana` | `grafana/grafana:latest` | `grafana-data` → `/var/lib/grafana` | `3001:3000` | Admin creds via `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` |
| `loki` | `grafana/loki:3.7.3` | `loki-data` → `/loki` | Internal `:3100` | `336h` (14d), `4MB/s` ingest (`8MB` burst), `2MB/s` per stream, `5000` max streams, `20` max labels, `256KB` line truncation, rejects samples older than `168h` |
| `prometheus` | `prom/prometheus:v3.13.1` | `prometheus-data` → `/prometheus` | Internal `:9090` | `30d` or `10GB` (whichever hits first); `--web.enable-remote-write-receiver` |
| `tempo` | `grafana/tempo:2.10.2` | `tempo-data` → `/var/tempo` | Internal `:3200` (HTTP), `:4317` (OTLP gRPC) | `336h` (14d), `5MB/s` ingest (`10MB` burst), `5000` max traces/user, `5MB` max/trace |
| `alloy` | `grafana/alloy:v1.17.1` | `alloy-data` → `/var/lib/alloy/data` + `/var/run/docker.sock` | `${TAILNET_IP}:4317` (OTLP gRPC), `${TAILNET_IP}:3101` (Loki push) | `512MiB` OTLP memory limiter, `4MiB` max gRPC/HTTP message size |

> **Security Note on Port Binding**: Alloy's remote ingestion ports (`4317`, `3101`) are explicitly bound to `var.TAILNET_IP` (validated to be in Tailscale's CGNAT range `100.64.0.0/10`) rather than `0.0.0.0`, because Docker published ports bypass host firewall rules.

### Telemetry Pipelines (`configs/alloy.alloy`)

1. **Logs**:
   - **Local**: `discovery.docker` tails `/var/run/docker.sock`, strips leading `/` from container name into label `container`, and tags `{ job = "docker", host = "jackserver" }`.
   - **Remote**: `loki.source.api "remote"` listens on `:3101` for logs pushed by remote Alloy agents on other tailnet boxes (which arrive pre-labelled with their own `host`).
   - **Scrubbing (`loki.process.scrub`)**:
     - Universal redaction (`[REDACTED]`) for `client_id`, `client_secret`, `access_token`, `refresh_token` (query/KV and JSON forms) and `Bearer <token>`.
     - App-scoped redaction for `{container=~"convex-osu-proxy.*"}`: redacts `k`, `b`, `mp`, `u` params/JSON keys and `/v2/(users|matches|beatmaps)/<id>` path segments.
   - **Sink**: `http://loki:3100/loki/api/v1/push`.

2. **OTLP Metrics & Traces**:
   - **Receiver**: `otelcol.receiver.otlp` listens on `:4317` (gRPC, published on tailnet) and `:4318` (HTTP, internal `observability` network).
   - **Backpressure**: `otelcol.processor.memory_limiter` (`512MiB`, checked every `1s`) sheds load before Alloy can OOM.
   - **Trace Scrubbing**: `otelcol.processor.attributes "scrub_traces"` deletes `url.full`, `url.query`, `url.path`, `http.url`, and `http.target` from spans before batching (preserving `http.route`, method, and status).
   - **Sinks**: Traces → `tempo:4317` (insecure gRPC); Metrics → `otelcol.exporter.prometheus` → `prometheus:9090/api/v1/write`.

3. **Infrastructure Self-Monitoring**:
   - `prometheus.scrape "infra"` scrapes `prometheus:9090`, `loki:3100`, and `alloy:12345`, forwarding via remote-write to Prometheus.

### Grafana Provisioning
- **Datasources** (`configs/grafana-datasources.yml`):
  - `Prometheus` (`uid: prometheus`, default)
  - `Loki` (`uid: loki`) — extracts `"trace_id":"([0-9a-f]+)"` as a derived field linking directly to Tempo.
  - `Tempo` (`uid: tempo`) — `tracesToLogsV2` links spans back to Loki filtered by trace ID (`-5m` to `+5m`).
- **Dashboards** (`configs/grafana-dashboards.yml` + `containers.tf`):
  - Terraform uses `fileset("${path.module}/configs/dashboards", "**/*.json")` to upload every JSON file into `/etc/grafana/dashboards/<folder>/<file>.json`.
  - Grafana's `foldersFromFilesStructure: true` turns each subdirectory into a Grafana folder.
  - Currently provisioned:
    - `platform/service-overview.json` — Generic RED (Rate, Errors, Duration) dashboard templated by `job`.
    - `convex-osu-proxy/osu-proxy.json` — Service-specific dashboard for `convex-osu-proxy`.

---

## 4. Reverse Proxy (`caddy/` on `terraform` box)

A single `caddy:2` container owns host ports `80`, `443`, and `443/udp` on the terraform box and routes traffic to application containers over the shared external Docker network `edge`.

### Routed Sites (`caddy/site/Caddyfile`)

| Domain | Upstream (`edge` network) | Origin Cert Files (`/etc/caddy/certs/`) |
| :--- | :--- | :--- |
| `uss.convex.coffee` | `uss-app:3000` | `convex-coffee-origin.pem` / `.key` |
| `lelastechcup.com` | `ltc-site-web:3000` | `ltc-origin.pem` / `.key` |
| `dans.convex.coffee` | `dans-app:3000` | `convex-coffee-origin.pem` / `.key` |
| `bot.convex.coffee` | `bot:3000` | `convex-coffee-origin.pem` / `.key` |

### TLS & Mount Rules
- **Cloudflare Origin Certificates only**: Every domain is proxied through Cloudflare with SSL/TLS mode set to **Full (strict)**. Certificates are per zone (e.g., `*.convex.coffee` wildcard shared across subdomains; `lelastechcup.com` has its own).
- **No ACME / Let's Encrypt**: ACME challenges cannot complete through Cloudflare's edge TLS termination. Always supply explicit `tls` directives.
- **Directory Bind Mount**: `caddy/docker-compose.yml` mounts `./site:/etc/caddy/site:ro` (a directory), **never** `./site/Caddyfile:/etc/caddy/Caddyfile`. Single-file bind mounts pin the container to the original inode, causing `git pull` + `caddy reload` to silently keep reading the stale file.
- **Certificate Hygiene**: `caddy/certs/` is gitignored and written on every deploy with `umask 077`. The deploy script aborts before modifying anything if any required cert/key secret is empty, and runs `caddy validate` in a throwaway container before touching the live proxy.

---

## 5. Terraform & Atlantis Automation

- **Atlantis (`atlantis/docker-compose.yml`)** runs on the **terraform box** with `network_mode: host`, mounting:
  - `~/.ssh/atlantis_id_rsa` → `/home/atlantis/.ssh/id_rsa:ro` (for SSHing into `jackserver`)
  - `atlantis-data` → `/home/atlantis/.atlantis` (persists Atlantis data and Terraform local state)
  - `./repos.yaml` → `/etc/atlantis/repos.yaml:ro` (enables `allow_custom_workflows: true`)
- **Autoplan (`atlantis.yaml`)**: Automatically runs `terraform init -reconfigure` and `terraform plan` on PRs modifying `*.tf`, `configs/*`, or `atlantis/docker-compose.yml`. Apply is triggered via Atlantis PR workflow (`atlantis apply`).
- **State Location (`backend.tf`)**: Local backend inside the Atlantis persistent volume at `/home/atlantis/.atlantis/tfstate/convex-infra/terraform.tfstate`.

---

## 6. CI/CD Workflows & Secrets

Both GitHub Actions workflows run on `push` to `main` (path-filtered) or `workflow_dispatch`, join the Tailscale network ephemerally via OIDC (`tailscale/github-action@v4.1.3`, `tags: tag:ci`), and SSH to `DEPLOY_HOST` (`appleboy/ssh-action@v1.2.5`) verifying the **ECDSA** host key fingerprint. Both share `concurrency.group: terraform-box` (`cancel-in-progress: false`) so they never race on `git pull` in `~/repos/convex-infra`.

| Workflow | Triggers (`main`) | Actions on `terraform` box |
| :--- | :--- | :--- |
| `.github/workflows/deploy-atlantis.yml` | `atlantis/**`, workflow file | `git pull`, stops/removes old `atlantis`, ensures `atlantis_atlantis-data` ownership (`100:1000`), starts `atlantis/docker-compose.yml` with env vars. |
| `.github/workflows/deploy-caddy.yml` | `caddy/**`, workflow file | `git pull`, verifies non-empty cert secrets, writes `caddy/certs/*` (`umask 077`), ensures `edge` network exists, pulls image, validates Caddyfile in throwaway container, `docker compose up -d --remove-orphans`, retries graceful `caddy reload` up to 5×, prunes old images. |

### Required GitHub Secrets & Variables

| Name | Type | Used By | Purpose |
| :--- | :--- | :--- | :--- |
| `TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE` | Secret | Both workflows | Tailscale OIDC auth for CI runner |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `SSH_HOST_FINGERPRINT` | Secret | Both workflows | SSH connection to terraform box over tailnet (ECDSA fingerprint) |
| `CONVEX_COFFEE_ORIGIN_CERT`, `CONVEX_COFFEE_ORIGIN_KEY` | Secret | `deploy-caddy` | Cloudflare Origin Cert for `*.convex.coffee` |
| `LTC_ORIGIN_CERT`, `LTC_ORIGIN_KEY` | Secret | `deploy-caddy` | Cloudflare Origin Cert for `lelastechcup.com` |
| `ATLANTIS_GH_APP_ID`, `ATLANTIS_PORT`, `ATLANTIS_REPO_ALLOWLIST` | Var | `deploy-atlantis` | Atlantis GitHub App & server config |
| `ATLANTIS_GH_APP_KEY`, `ATLANTIS_GH_WEBHOOK_SECRET` | Secret | `deploy-atlantis` | Atlantis GitHub App key & webhook secret |
| `SERVER_USER`, `SERVER_HOST` | Secret | `deploy-atlantis` | Terraform `TF_VAR_*` for SSH to jackserver |
| `GF_SECURITY_ADMIN_USER`, `GF_SECURITY_ADMIN_PASSWORD` | Secret | `deploy-atlantis` | Terraform `TF_VAR_*` for Grafana admin login |
| `TAILNET_IP` | Var | `deploy-atlantis` | Terraform `TF_VAR_TAILNET_IP` (jackserver Tailscale IPv4) |

---

## 7. Firewall & Utility Scripts

### Linode Cloud Firewall Sync (`scripts/update-cloudflare-firewall.ts`)
The terraform box's Linode Cloud Firewall has an inbound policy of `DROP` and admits TCP ports `80` and `443` **only** from Cloudflare's IPv4/IPv6 ranges (so origin traffic cannot bypass Cloudflare).

```sh
# Preview changes (default, makes no API writes)
LINODE_TOKEN=<token> bun scripts/update-cloudflare-firewall.ts <firewall-id>

# Apply updated Cloudflare IP ranges
LINODE_TOKEN=<token> bun scripts/update-cloudflare-firewall.ts <firewall-id> --apply
```

Safety guards built into the script:
- Refuses to modify the firewall unless `inbound_policy === "DROP"` and there is **exactly one** inbound `ACCEPT TCP` rule for port `80` and one for port `443`.
- Validates fetched Cloudflare CIDR lists against IPv4/IPv6 regexes before writing.
- Preserves all other inbound rules, outbound rules, and policies unchanged.

---

## 8. Common Tasks & Pre-Commit Verification

### Adding a New Site to Caddy
1. In the app's own repo, connect its web container to the external Docker network `edge` with a unique container name.
2. Add a site block to `caddy/site/Caddyfile` pointing `reverse_proxy` to `<container-name>:<port>`.
3. For a `*.convex.coffee` subdomain, reuse `/etc/caddy/certs/convex-coffee-origin.{pem,key}`.
4. For a **new apex domain/zone**:
   - Create a Cloudflare Origin Certificate (zone SSL/TLS mode: **Full (strict)**).
   - Add `<ZONE>_ORIGIN_CERT` and `<ZONE>_ORIGIN_KEY` to GitHub repository secrets.
   - Update `.github/workflows/deploy-caddy.yml` (`envs:`, `env:`, non-empty validation loop, and `printf` write to `certs/`).

### Adding a New Grafana Dashboard
- Drop the exported JSON into `configs/dashboards/<folder-name>/<dashboard-name>.json`.
- Open a PR; Terraform's dynamic `upload` block will provision it into the `<folder-name>` folder in Grafana.

### Pre-Commit Verification Commands
Run these before opening a PR when modifying Terraform or observability configs:

```sh
# Terraform formatting and syntax
terraform fmt -check
terraform validate

# Alloy config
docker run --rm -v "${PWD}/configs/alloy.alloy:/c.alloy:ro" grafana/alloy:v1.17.1 validate /c.alloy

# Loki config
docker run --rm -v "${PWD}/configs/loki.yml:/etc/loki/loki.yml:ro" grafana/loki:3.7.3 -config.file=/etc/loki/loki.yml -verify-config

# Tempo config
docker run --rm -v "${PWD}/configs/tempo.yml:/etc/tempo/tempo.yml:ro" grafana/tempo:2.10.2 -config.file=/etc/tempo/tempo.yml -config.verify

# Prometheus config
docker run --rm -v "${PWD}/configs/prometheus.yml:/etc/prometheus/prometheus.yml:ro" prom/prometheus:v3.13.1 --config.file=/etc/prometheus/prometheus.yml --web.enable-remote-write-receiver
```

---

## 9. Critical Invariants (Do Not Break)

1. **One Alloy agent per host**: Never add a second Alloy container to a box that already runs one—two agents tailing `/var/run/docker.sock` duplicate every container's logs.
2. **Tailscale-only telemetry exposure**: Never publish Alloy ports `4317` or `3101` on `0.0.0.0`; always bind to `var.TAILNET_IP`.
3. **Directory mount for Caddyfile**: Never change `./site:/etc/caddy/site:ro` to a single-file bind mount.
4. **No ACME in Caddy**: All sites are behind Cloudflare; always use Cloudflare Origin Certificates.
5. **Cloudflare-only HTTP/HTTPS ingress**: Every site hosted on the terraform box must be proxied through Cloudflare, otherwise the Linode Cloud Firewall will drop direct client traffic.
6. **Concurrency on `terraform-box`**: Keep `concurrency.group: terraform-box` on any workflow that pulls `~/repos/convex-infra` on the terraform box.
