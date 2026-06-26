# uptime-runner

External HTTP probes for hostnames that the target service cannot probe
itself (e.g. Cloudflare Worker self-loop limitations). One workflow per
target. Public repo for unlimited Actions minutes.

## Public-repo policy

This repo is public. Workflow YAML **and workflow run logs** are
world-readable. To avoid leaking recon signal:

1. **Never put a hostname, endpoint path, or any identifying URL in a
   workflow YAML file.** Move them into repo secrets.
2. **Never name a workflow file after the target.** Use opaque names
   like `target-1.yml`, `target-2.yml`. Pairing a public filename with
   even a public hostname makes scraping trivial.
3. **Never echo response bodies, payloads, hostnames, or response
   shapes to stdout.** GitHub workflow run logs at
   `github.com/<owner>/<repo>/actions/runs/<id>/logs` are publicly
   accessible for the lifetime of the run (default 90 days). Print
   only counts + HTTP status codes. If you must debug payload shape,
   do it locally with `act` or in a private fork.
4. The README + template + lib are fine to be public — they describe
   the mechanism, not which targets are wired up.

### Cleaning up leaked past runs

If you discover a workflow has been logging payload contents, deleting
the workflow runs is necessary because GitHub does not allow editing
run logs in place:

- UI: Actions tab → workflow → click the run → top-right `...` menu →
  "Delete workflow run"
- gh CLI: `gh run delete <run-id>` (for each affected run)
- Or temporarily make the repo private until logs expire (90 days)

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

## Contracts — two distinct target shapes

This repo currently runs two unrelated probe contracts. Each target
YAML implements ONE; do not mix.

### Contract A — domain/partner uptime probe (`target-1.yml`)

**LIST endpoint** (read-only, no mutation):

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

**REPORT endpoint**:

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

### Contract B — per-tracker persona probe (`target-2.yml`)

**LIST endpoint** (read-only, returns active trackers + cloak URLs):

```http
GET <LIST_URL>
X-Internal-Auth: <TOKEN>

200 OK
{
  "ok": true,
  "trackers": [
    {
      "tracker_id": <int>,
      "tracker_name": "<str>",
      "cloak_url": "https://<sub>.<apex>",
      "money_url": "https://<money-host>/...",
      "partner_id": <int|null>,
      "partner_name": "<str|null>"
    },
    ...
  ]
}
```

**REPORT endpoint** — per-tracker per-persona verdict ingest:

```http
POST <REPORT_URL>
X-Internal-Auth: <TOKEN>
Content-Type: application/json

{
  "reports": [
    {
      "trackerId": <int>,
      "persona": "human" | "bot" | "fb_crawler" | "fb_ad_review",
      "status": <int>,
      "location": "<str>",
      "error": <null|str>,
      "checkedAt": <unix>
    },
    ...
  ]
}
```

Both contracts share: 5xx response on persistent write failure so the
runner job fails red, token gate enforced by target.

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
