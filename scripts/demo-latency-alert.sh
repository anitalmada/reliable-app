#!/usr/bin/env bash
# Inject payment latency and wait until fast-burn PAGE alert fires.
set -euo pipefail

PAYMENTS="${PAYMENTS_URL:-http://127.0.0.1:8083}"
CHECKOUT="${CHECKOUT_URL:-http://127.0.0.1:8082}"
PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
INBOX_URL="${INBOX_URL:-http://127.0.0.1:8084}"
TMPDIR="${TMPDIR:-/tmp}"

log() { printf '==> %s\n' "$*"; }

log "Clear inbox"
curl -fsS -X DELETE "${INBOX_URL}/inbox" >/dev/null || true

# Fresh counters so 5m + 1h windows are dominated by slow traffic (MWMBR needs both).
if command -v kubectl >/dev/null 2>&1; then
  log "Restart checkout-api + payments-mock for clean windows"
  kubectl -n reliable-app rollout restart deploy/checkout-api deploy/payments-mock
  kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s
  kubectl -n reliable-app rollout status deploy/payments-mock --timeout=90s
fi

log "Wait for payments-mock to accept traffic"
for _ in $(seq 1 60); do
  if curl -fsS "${PAYMENTS}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

log "Reset faults then inject 2s payment latency"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0,"timeout":false}' >/dev/null

log "Generate slow payment traffic for ~2 minutes"
for i in $(seq 1 40); do
  ID=$(curl -fsS -X POST "${CHECKOUT}/checkout" \
    -H 'Content-Type: application/json' \
    -d '{"items":[{"product_id":1,"quantity":1,"unit_price_cents":1500}],"total_cents":1500,"currency":"USD"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  curl -s -o /dev/null -w "pay %{http_code}\n" --max-time 10 \
    -X POST "${CHECKOUT}/checkout/${ID}/pay" || true
  sleep 3
done

log "Waiting for Prometheus evaluation (for: 1m)..."
sleep 75

log "Firing alerts containing PaymentLatency"
curl -fsS --get "${PROM_URL}/api/v1/alerts" -o "${TMPDIR}/reliable-alerts.json"
python3 - "${TMPDIR}/reliable-alerts.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    alerts = json.load(f).get("data", {}).get("alerts", [])
hits = [
    a for a in alerts
    if a.get("state") == "firing"
    and "PaymentLatency" in a.get("labels", {}).get("alertname", "")
]
if not hits:
    print("FAIL: ErrorBudgetBurnFastPaymentLatency not firing yet", file=sys.stderr)
    print("Tip: keep generating slow traffic; increase() windows need samples.", file=sys.stderr)
    sys.exit(1)
for a in hits:
    print("OK:", a["labels"].get("alertname"), "severity=", a["labels"].get("severity"))
    print(" ", a.get("annotations", {}).get("description", "")[:160])
PY

log "Inbox pager queue (should be non-empty)"
curl -fsS "${INBOX_URL}/inbox" -o "${TMPDIR}/reliable-inbox.json"
python3 - "${TMPDIR}/reliable-inbox.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    inbox = json.load(f)
n = inbox.get("pager_count", 0)
print(f"pager_count={n} ticket_count={inbox.get('ticket_count', 0)}")
if n < 1:
    print("WARN: pager inbox empty — Alertmanager may still be delivering", file=sys.stderr)
    sys.exit(0)
print("OK: P1 webhook delivered to alert-inbox /pager")
PY

log "Reset faults"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

log "Done — see also ./scripts/check-alerts.sh"
