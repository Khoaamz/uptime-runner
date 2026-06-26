# uptime-runner

External HTTP probes for hostnames that the target service cannot probe
itself (e.g. Cloudflare Worker self-loop limitations). One workflow per
target. Public repo for unlimited Actions minutes.

## Public-repo policy

This repo is public. Workflow YAML is world-readable. To avoid leaking
recon signal:

1. **Never put a hostname, endpoint path, or any identifying URL in a
   workflow YAML file.** Move them into repo secrets.
2. **Never name a workflow file after the target.** Use opaque names
   like `target-1.yml`, `target-2.yml`. Pairing a public filename with
   even a public hostname makes scraping trivial.
3. The README + template + lib are fine to be public — they describe
   the mechanism, not which targets are wired up.

If you must store identifying info in YAML (e.g. for an audit trail
that ties workflows to projects), keep this repo private and accept
the Actions-minute budget tradeoff (2,000/month for the Free plan, or
buy Pro for 3,000).

## Layout

```
uptime-runner/
├── .github/workflows/
│   ├── target-1.yml             # opaque per-target probe
│   ├── target-2.yml
│   └── _template.yml.sample     # copy + rename
└── lib/
    └── probe.sh                 # shared HEAD-probe helper
```

## Adding a new target

1. Copy `_template.yml.sample` to `target-<N>.yml`.
2. In **Repo Settings → Secrets and variables → Actions**, add three
   secrets per target. For `target-2.yml` they'd be:
   - `TARGET_2_LIST_URL`   read-only endpoint returning `{ok, domains:[{domain, …}]}`
   - `TARGET_2_REPORT_URL` ingest endpoint accepting `{checks:[{host, status, …}]}`
   - `TARGET_2_TOKEN`      bearer for the `X-Internal-Auth` header
3. Update the env block in the workflow YAML to reference the matching
   secret names.
4. Commit + push. First scheduled run fires inside 15 minutes.

## Contract the target service must implement

**List endpoint** (read-only, no mutation):

```http
GET <LIST_URL>
X-Internal-Auth: <TOKEN>

200 OK
{
  "ok": true,
  "domains": [
    { "domain": "<host>", ...optional-metadata },
    ...
  ]
}
```

**Report endpoint** (writes audit + decides alerts):

```http
POST <REPORT_URL>
X-Internal-Auth: <TOKEN>
Content-Type: application/json

{
  "checks": [
    {
      "host": "<host>",
      "status": <int|null>,
      "location": "<str|null>",
      "error": "<str|null>",
      "checkedAt": <unix>
    },
    ...
  ]
}
```

Report response should be 5xx on persistent write failure so the
runner job fails red. Token gate enforced by target.

## Schedule cost

Public repo → unlimited Actions minutes. `*/15` (4 runs/hour) is the
sweet spot: fast enough to catch most outages, slow enough to keep
costs trivial.

For private repos, see GitHub Actions pricing — most cadences blow
through the 2,000-minute free tier.

## What this is NOT

- Not a full uptime monitor (no historical graph, no PagerDuty). The
  probe just fires curl and POSTs back; the target owns storage +
  alert dispatch.
- Not self-hosted on the same infra as the target. If a CF Worker
  fronts the host, the probe must come from outside CF.
- Not project-specific. Each workflow is one target; the scaffolding
  is reusable.
