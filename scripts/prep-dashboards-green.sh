#!/usr/bin/env bash
# Reset chaos, refresh API counters, and generate healthy traffic so Executive
# budgets show green before a demo / recording.
set -euo pipefail

PAYMENTS="${PAYMENTS_URL:-http://127.0.0.1:8083}"
CHECKOUT="${CHECKOUT_URL:-http://127.0.0.1:8082}"
CATALOG="${CATALOG_URL:-http://127.0.0.1:8081}"
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
COUNT="${HEALTHY_REQUESTS:-20}"

log() { printf '==> %s\n' "$*"; }

log "Reset payment faults"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

if command -v kubectl >/dev/null 2>&1; then
  log "Restart APIs (clears lifetime counters; self-heal restarts wipe /charge histograms)"
  kubectl -n reliable-app rollout restart \
    deploy/catalog-api deploy/checkout-api deploy/payments-mock
  kubectl -n reliable-app rollout status deploy/catalog-api --timeout=90s
  kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s
  kubectl -n reliable-app rollout status deploy/payments-mock --timeout=90s
fi

log "Wait for health"
for _ in $(seq 1 60); do
  if curl -fsS "${CATALOG}/health" >/dev/null 2>&1 \
    && curl -fsS "${CHECKOUT}/health" >/dev/null 2>&1 \
    && curl -fsS "${PAYMENTS}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

log "Generate ${COUNT} healthy catalog + checkout/pay requests"
for i in $(seq 1 "${COUNT}"); do
  curl -fsS "${CATALOG}/products" >/dev/null
  ID="$(curl -fsS -X POST "${CHECKOUT}/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"items":[{"product_id":1,"quantity":1,"unit_price_cents":1500}],"total_cents":1500,"currency":"USD"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${CHECKOUT}/checkout/${ID}/pay")"
  printf '  %02d pay -> %s\n' "${i}" "${CODE}"
  test "${CODE}" = "200" || { echo "WARN: expected HTTP 200, got ${CODE}" >&2; }
done

log "Wait for Prometheus scrapes so increase() is non-zero (~45s)"
sleep 45

log "Error budgets (want availability / payment_latency / checkout_success near 100%)"
./scripts/query-error-budget.sh

curl -fsS --get "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=slo:error_budget_remaining:ratio' \
  -o /tmp/reliable-budget-prep.json
python3 - <<'PY'
import json, math, sys
rows = json.load(open("/tmp/reliable-budget-prep.json", encoding="utf-8"))["data"]["result"]
by_slo = {r["metric"].get("slo", "?"): float(r["value"][1]) for r in rows}
expected = ("availability", "payment_latency", "checkout_success")
bad = []
for slo in expected:
    val = by_slo.get(slo, float("nan"))
    print(f"  {slo:20s}  remaining={val}")
    if math.isnan(val) or val < 0.5:
        bad.append(slo)
if bad:
    print("WARN: still not green for:", ", ".join(bad), file=sys.stderr)
    print("Tip: re-run this script; ensure faults are off and pays return 200.", file=sys.stderr)
    sys.exit(1)
print("OK: Executive budgets should be green — safe to start recording.")
PY
