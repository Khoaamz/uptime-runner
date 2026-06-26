#!/usr/bin/env bash
# Per-tracker per-persona probe helper.
#
# Extracted from inline target-2.yml logic (audit P3 §7, 2026-06-27).
# Keeps timeout / UA / location parsing in one place so target-1's
# probe.sh and target-2's persona probe share the same shape rules.
#
# Stdin: JSON-lines stream of tracker rows
#        { "tracker_id": <int>, "cloak_url": "https://..." }
#
# Stdout: JSON array of report rows
#         [{ "trackerId": <int>, "persona": "human"|"bot"|"fb_crawler"|"fb_ad_review",
#            "status": <int>, "location": "<str>", "error": <null|str>,
#            "checkedAt": <unix> }, ...]
#
# Public-repo policy (audit §8): NEVER echo tracker IDs, cloak URLs,
# money URLs, or response bodies to stdout outside the final JSON.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERR: jq is required" >&2
  exit 3
fi

UA_HUMAN='Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126 Mobile/15E148 Safari/604.1'
UA_BOT='Mozilla/5.0 (compatible; HeadlessChrome/124.0.0.0) AppleWebKit/537.36'
UA_FB_CRAWLER='facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'
UA_FB_AD_REVIEW='Mozilla/5.0 (compatible; meta-externalagent/1.1; +https://developers.facebook.com/docs/sharing/webmasters/crawler)'

probe_one() {
  local tid="$1" cloak="$2" persona="$3" ua now hdrs status location
  case "$persona" in
    human) ua="$UA_HUMAN" ;;
    bot) ua="$UA_BOT" ;;
    fb_crawler) ua="$UA_FB_CRAWLER" ;;
    fb_ad_review) ua="$UA_FB_AD_REVIEW" ;;
    *) ua="$UA_HUMAN" ;;
  esac
  now=$(date +%s)
  hdrs=$(curl -sI --max-time 8 --connect-timeout 4 -A "$ua" "$cloak" 2>/dev/null || true)
  status=$(echo "$hdrs" | awk 'NR==1{print $2}')
  location=$(echo "$hdrs" | awk 'tolower($1)=="location:"{print $2; exit}' | tr -d '\r')
  jq -n \
    --argjson tid "$tid" \
    --arg p "$persona" \
    --argjson s "${status:-0}" \
    --arg l "${location:-}" \
    --argjson e null \
    --argjson t "$now" \
    '{trackerId: $tid, persona: $p, status: $s, location: $l, error: $e, checkedAt: $t}'
}

OUT='[]'
while IFS= read -r row; do
  [ -z "$row" ] && continue
  TID=$(echo "$row" | jq -r '.tracker_id')
  CLOAK=$(echo "$row" | jq -r '.cloak_url')
  for persona in human bot fb_crawler fb_ad_review; do
    REPORT=$(probe_one "$TID" "$CLOAK" "$persona")
    OUT=$(echo "$OUT" | jq --argjson r "$REPORT" '. + [$r]')
  done
done

echo "$OUT"
