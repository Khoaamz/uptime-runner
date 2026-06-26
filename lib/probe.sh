#!/usr/bin/env bash
# Shared HEAD-probe helper.
#
# Args: each positional argument is a host. Stdout is a JSON array of
# {host, status, location, error, checkedAt} entries.
#
# Caller is responsible for:
#   - fetching the list of hosts (from API or hardcoded)
#   - reading the result + POSTing to the target's report endpoint
#
# Why HEAD: cheap (no body download), fast (avoids slow first-byte on
# heavy pages), and matches the contract we want to enforce (302 +
# Location header). For targets that need GET semantics (e.g. body
# inspection), write a separate helper.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <host1> [host2 …]" >&2
  exit 2
fi

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERR: jq is required (install with: sudo apt install jq)" >&2
    exit 3
  fi
}
require_jq

OUT='[]'
for host in "$@"; do
  now=$(date +%s)
  tmperr=$(mktemp)
  hdrs=$(curl -sI --max-time 10 --connect-timeout 5 \
    -A "uptime-runner/1.0 (+https://github.com/khoaamz/uptime-runner)" \
    "https://${host}/" 2>"$tmperr" || true)
  err=$(cat "$tmperr"); rm -f "$tmperr"
  status=$(echo "$hdrs" | awk 'NR==1{print $2}')
  location=$(echo "$hdrs" | awk 'tolower($1)=="location:"{print $2; exit}' | tr -d '\r')
  err_field="null"
  if [ -z "$status" ] && [ -n "$err" ]; then
    err_field=$(jq -Rs <<<"$err")
  fi
  status_field=${status:-0}
  OUT=$(echo "$OUT" | jq \
    --arg h "$host" \
    --argjson s "$status_field" \
    --arg l "${location:-}" \
    --argjson e "$err_field" \
    --argjson t "$now" \
    '. + [{host: $h, status: $s, location: $l, error: $e, checkedAt: $t}]')
done

echo "$OUT"
