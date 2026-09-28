/**
 * Limits the terraform box's Linode Cloud Firewall HTTP and HTTPS rules to
 * Cloudflare's published IP ranges, so visitors can only reach the sites on it
 * (see caddy/) through Cloudflare. Every other rule, both default policies and
 * the outbound rules are written back exactly as they were.
 *
 * The Linode API replaces a firewall's whole ruleset on every update, so this
 * reads the current rules, swaps the sources of the two web rules (the
 * inbound TCP rules allowing port 80 and port 443), and writes the set back.
 * Run it again whenever Cloudflare changes its ranges.
 *
 *   bun scripts/update-cloudflare-firewall.ts <firewall id>          # preview
 *   bun scripts/update-cloudflare-firewall.ts <firewall id> --apply  # update
 *
 * Reads a Linode personal access token with Firewalls read/write access from
 * LINODE_TOKEN, and never prints it.
 */

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const LINODE_API = "https://api.linode.com/v4";

const CLOUDFLARE_LISTS = {
  ipv4: {
    url: "https://www.cloudflare.com/ips-v4",
    pattern: /^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/,
  },
  ipv6: {
    url: "https://www.cloudflare.com/ips-v6",
    pattern: /^[0-9a-f:]+\/\d{1,3}$/i,
  },
};

/** The web rules are the inbound TCP rules allowing exactly these ports. */
const WEB_PORTS = ["80", "443"];

export type FirewallRule = {
  action: "ACCEPT" | "DROP";
  protocol: string;
  ports?: string;
  addresses: { ipv4?: string[]; ipv6?: string[] };
  label?: string;
  description?: string;
};

export type Ruleset = {
  inbound: FirewallRule[];
  inbound_policy: "ACCEPT" | "DROP";
  outbound: FirewallRule[];
  outbound_policy: "ACCEPT" | "DROP";
};

export type IpRanges = { ipv4: string[]; ipv6: string[] };

function isWebRule(rule: FirewallRule, port?: string): boolean {
  const ports = rule.ports?.replace(/\s/g, "");
  return (
    rule.action === "ACCEPT" &&
    rule.protocol === "TCP" &&
    (port ? ports === port : WEB_PORTS.some((web) => ports === web))
  );
}

/**
 * The ruleset with the two web rules admitting only `cloudflare`; every other
 * rule and both policies are returned as they are. Throws, so nothing gets
 * written, unless there's exactly one web rule per port and traffic matching
 * no rule is dropped (with an ACCEPT inbound policy the restriction would do
 * nothing).
 */
export function restrictWebRules(current: Ruleset, cloudflare: IpRanges): Ruleset {
  if (current.inbound_policy !== "DROP") {
    throw new Error(
      "The firewall's inbound policy is ACCEPT, so traffic matching no rule is let in anyway and restricting the web rules would do nothing. Nothing was changed.",
    );
  }
  for (const port of WEB_PORTS) {
    const count = current.inbound.filter((rule) => isWebRule(rule, port)).length;
    if (count !== 1) {
      throw new Error(
        `Expected one inbound TCP rule allowing port ${port}, found ${count}. Nothing was changed.`,
      );
    }
  }

  return {
    inbound: current.inbound.map((rule) =>
      isWebRule(rule)
        ? { ...rule, addresses: { ipv4: cloudflare.ipv4, ipv6: cloudflare.ipv6 } }
        : rule,
    ),
    inbound_policy: current.inbound_policy,
    outbound: current.outbound,
    outbound_policy: current.outbound_policy,
  };
}

async function fetchCloudflareRanges(): Promise<IpRanges> {
  const fetchList = async ({ url, pattern }: { url: string; pattern: RegExp }) => {
    const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
    if (!response.ok) throw new Error(`Fetching ${url} failed with ${response.status}.`);
    const ranges = (await response.text()).split(/\s+/).filter(Boolean);
    // An empty or garbled list would shut visitors out, so refuse it.
    if (ranges.length === 0 || !ranges.every((range) => pattern.test(range))) {
      throw new Error(`${url} didn't return a list of IP ranges. Nothing was changed.`);
    }
    return ranges;
  };

  const [ipv4, ipv6] = await Promise.all([
    fetchList(CLOUDFLARE_LISTS.ipv4),
    fetchList(CLOUDFLARE_LISTS.ipv6),
  ]);
  return { ipv4, ipv6 };
}

async function linode<T>(
  path: string,
  { method = "GET", body }: { method?: string; body?: unknown } = {},
): Promise<T> {
  const token = process.env.LINODE_TOKEN;
  if (!token) {
    throw new Error(
      "Set LINODE_TOKEN to a Linode personal access token with Firewalls read/write access.",
    );
  }

  const response = await fetch(`${LINODE_API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  const result = (await response.json().catch(() => null)) as {
    errors?: unknown;
  } | null;
  if (!response.ok) {
    throw new Error(
      `Linode API ${method} ${path} failed with ${response.status}: ${JSON.stringify(result?.errors ?? result)}`,
    );
  }
  return result as T;
}

function describeRule(rule: FirewallRule): string {
  const ranges = [...(rule.addresses.ipv4 ?? []), ...(rule.addresses.ipv6 ?? [])];
  const from = ranges.some((range) => range === "0.0.0.0/0" || range === "::/0")
    ? "anywhere"
    : `${ranges.length} ranges`;
  return `${(rule.label ?? "(no label)").padEnd(20)} ${rule.action} ${rule.protocol} ${rule.ports ?? "all ports"} from ${from}`;
}

export async function run(args: string[]): Promise<void> {
  const [firewallId, ...flags] = args;
  if (
    !firewallId ||
    !/^\d+$/.test(firewallId) ||
    flags.some((flag) => flag !== "--apply")
  ) {
    throw new Error(
      "Usage: bun scripts/update-cloudflare-firewall.ts <firewall id> [--apply]",
    );
  }

  const path = `/networking/firewalls/${firewallId}/rules`;
  const current = await linode<Ruleset>(path);
  const next = restrictWebRules(current, await fetchCloudflareRanges());

  console.log("Inbound rules:");
  next.inbound.forEach((rule, index) => {
    console.log(
      isWebRule(rule)
        ? `  ${describeRule(current.inbound[index])}\n    -> ${describeRule(rule)}`
        : `  ${describeRule(rule)}  (unchanged)`,
    );
  });
  console.log(
    `Inbound policy ${next.inbound_policy}, outbound policy ${next.outbound_policy}, ${next.outbound.length} outbound rules (all unchanged).`,
  );

  if (!flags.includes("--apply")) {
    console.log(
      "\nPreview only: nothing was changed. Run again with --apply to update the firewall.",
    );
    return;
  }

  await linode(path, { method: "PUT", body: next });
  const updated = await linode<Ruleset>(path);
  console.log("\nUpdated. The firewall's inbound rules are now:");
  for (const rule of updated.inbound) console.log(`  ${describeRule(rule)}`);
}

// Runs when invoked directly; importing the module (as a test does) doesn't.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run(process.argv.slice(2)).catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
