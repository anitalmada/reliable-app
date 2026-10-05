#!/usr/bin/env bash
# Print remaining error budget for each SLO from Prometheus.
set -euo pipefail

PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
QUERY='slo:error_budget_remaining:ratio'

query() {
  local q="$1"
  curl -fsS --get "${PROM_URL}/api/v1/query" --data-urlencode "query=${q}"
}

log() { printf '==> %s\n' "$*"; }

log "Prometheus ${PROM_URL}"
log "Query: ${QUERY}"

JSON="$(query "${QUERY}")"
STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"${JSON}")"
test "${STATUS}" = "success" || { echo "${JSON}" >&2; exit 1; }

python3 - <<'PY' "${JSON}"
import json, sys
data = json.loads(sys.argv[1])
results = data.get("data", {}).get("result", [])
if not results:
    print("No series yet. Generate traffic (./scripts/smoke-test.sh) and wait ~15–30s for scrape + rules.")
    sys.exit(2)
print(f"{'SLO':<20} {'budget_remaining':>18} {'pct':>8}")
print("-" * 50)
for r in sorted(results, key=lambda x: x["metric"].get("slo", "")):
    slo = r["metric"].get("slo", "?")
    val = float(r["value"][1])
    print(f"{slo:<20} {val:>18.4f} {val*100:>7.1f}%")
PY
