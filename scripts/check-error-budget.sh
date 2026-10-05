#!/usr/bin/env bash
# CI-style gate: fail if any SLO error budget remaining is below the threshold.
set -euo pipefail

PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
MIN_REMAINING="0.20"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-remaining)
      MIN_REMAINING="$2"
      shift 2
      ;;
    --prom-url)
      PROM_URL="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--min-remaining 0.20] [--prom-url URL]" >&2
      exit 2
      ;;
  esac
done

JSON="$(curl -fsS --get "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=slo:error_budget_remaining:ratio')"

python3 - <<'PY' "${JSON}" "${MIN_REMAINING}"
import json, sys
data = json.loads(sys.argv[1])
min_remaining = float(sys.argv[2])
results = data.get("data", {}).get("result", [])
if not results:
    print("FAIL: no error-budget series (no traffic or rules not ready)", file=sys.stderr)
    sys.exit(1)
failed = []
for r in results:
    slo = r["metric"].get("slo", "?")
    val = float(r["value"][1])
    status = "OK" if val >= min_remaining else "FREEZE"
    print(f"{status}: {slo} budget_remaining={val:.4f} (min={min_remaining})")
    if val < min_remaining:
        failed.append(slo)
if failed:
    print(f"Deploy freeze: budget below threshold for: {', '.join(failed)}", file=sys.stderr)
    sys.exit(1)
print("Deploy gate passed")
PY
