#!/usr/bin/env bash
# Open the payments circuit breaker via fault injection; show 503 degraded.
set -euo pipefail

PAYMENTS="${PAYMENTS_URL:-http://127.0.0.1:8083}"
CHECKOUT="${CHECKOUT_URL:-http://127.0.0.1:8082}"
TMPDIR="${TMPDIR:-/tmp}"

log() { printf '==> %s\n' "$*"; }

create_and_pay() {
  local id http_code
  id="$(curl -fsS -X POST "${CHECKOUT}/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"items":[{"product_id":1,"quantity":1,"unit_price_cents":1500}],"total_cents":1500,"currency":"USD"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  set +e
  http_code="$(curl -sS -o "${TMPDIR}/reliable-cb-pay.json" -w '%{http_code}' \
    -X POST "${CHECKOUT}/checkout/${id}/pay")"
  set -e
  printf 'pay %s -> HTTP %s\n' "${id}" "${http_code}"
  echo "${http_code}"
}

log "Reset payment faults"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

# Fresh circuit state (in-process breaker lives in checkout-api).
if command -v kubectl >/dev/null 2>&1; then
  log "Restart checkout-api for a closed circuit"
  kubectl -n reliable-app rollout restart deploy/checkout-api
  kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s
fi

for _ in $(seq 1 30); do
  curl -fsS "${CHECKOUT}/health" >/dev/null 2>&1 && break
  sleep 1
done

log "Circuit before faults"
curl -fsS "${CHECKOUT}/circuit" | python3 -m json.tool

log "Inject 100% payment 5xx"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}' >/dev/null

log "Fail pays until circuit opens (threshold=3)"
for i in $(seq 1 4); do
  create_and_pay >/dev/null || true
done

log "Circuit after failures"
curl -fsS "${CHECKOUT}/circuit" -o "${TMPDIR}/reliable-circuit.json"
python3 - "${TMPDIR}/reliable-circuit.json" <<'PY'
import json, sys
snap = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(snap, indent=2))
if snap.get("state") != "open":
    raise SystemExit(f"FAIL: expected state=open, got {snap.get('state')}")
print("OK: circuit is OPEN")
PY

log "Next pay should be 503 degraded (no payments call)"
CODE="$(create_and_pay | tail -n1)"
test "${CODE}" = "503" || { echo "Expected HTTP 503, got ${CODE}" >&2; exit 1; }
python3 - "${TMPDIR}/reliable-cb-pay.json" <<'PY'
import json, sys
body = json.load(open(sys.argv[1], encoding="utf-8"))
detail = body.get("detail", "")
print(detail)
if "maintenance" not in detail.lower() and "circuit" not in detail.lower():
    raise SystemExit("FAIL: expected degraded/maintenance detail")
print("OK: degraded response while circuit open")
PY

log "Reset faults (circuit stays open until recovery timeout + probe success)"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

log "Done — see automation/circuit-breaker/README.md"
