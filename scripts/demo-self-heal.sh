#!/usr/bin/env bash
# Trigger self-heal via Alertmanager-shaped webhook; verify fault reset + restart.
set -euo pipefail

PAYMENTS="${PAYMENTS_URL:-http://127.0.0.1:8083}"
SELF_HEAL="${SELF_HEAL_URL:-http://127.0.0.1:8085}"
TMPDIR="${TMPDIR:-/tmp}"

log() { printf '==> %s\n' "$*"; }

log "Wait for self-heal"
for _ in $(seq 1 60); do
  if curl -fsS "${SELF_HEAL}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "${SELF_HEAL}/health" >/dev/null

log "Inject payment faults (simulating burn)"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0.5,"timeout":false}' >/dev/null
curl -fsS "${PAYMENTS}/admin/faults" | python3 -m json.tool

GEN="$(date -u +%Y%m%dT%H%M%SZ)"
BEFORE_RS=""
if command -v kubectl >/dev/null 2>&1; then
  BEFORE_RS="$(kubectl -n reliable-app get deploy/payments-mock \
    -o jsonpath='{.spec.template.metadata.annotations.reliable-app\.io/restartedAt}' 2>/dev/null || true)"
  log "payments-mock restartedAt (before): ${BEFORE_RS:-<none>}"
fi

log "POST Alertmanager-shaped PAGE webhook"
cat > "${TMPDIR}/reliable-self-heal-payload.json" <<EOF
{
  "receiver": "pager",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "ErrorBudgetBurnFastPaymentLatency",
        "severity": "page",
        "slo": "payment_latency"
      },
      "annotations": {
        "summary": "Demo PAGE burn — self-heal walkthrough",
        "description": "Synthetic Alertmanager payload for Phase 4"
      },
      "startsAt": "${GEN}",
      "generatorURL": "http://prometheus:9090"
    }
  ]
}
EOF

curl -fsS -X POST "${SELF_HEAL}/webhook" \
  -H 'Content-Type: application/json' \
  -d @"${TMPDIR}/reliable-self-heal-payload.json" \
  -o "${TMPDIR}/reliable-self-heal-result.json"
python3 -m json.tool < "${TMPDIR}/reliable-self-heal-result.json"

python3 - "${TMPDIR}/reliable-self-heal-result.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
if r.get("action") not in ("healed", "skipped"):
    raise SystemExit(f"FAIL: unexpected action={r.get('action')}")
if r.get("action") == "healed":
    restart = r.get("restart") or {}
    if restart.get("error"):
        raise SystemExit(f"FAIL: restart error: {restart['error']}")
    print("OK: heal action recorded")
else:
    print("OK: cooldown skip (prior heal within window) — still valid")
PY

log "Actions ledger"
curl -fsS "${SELF_HEAL}/actions" | python3 -m json.tool | head -n 40

log "Evidence files"
curl -fsS "${SELF_HEAL}/evidence" | python3 -m json.tool

# Faults should be cleared after a successful heal.
log "Payment faults after heal"
sleep 2
curl -fsS "${PAYMENTS}/admin/faults" -o "${TMPDIR}/reliable-faults.json"
python3 - "${TMPDIR}/reliable-faults.json" "${TMPDIR}/reliable-self-heal-result.json" <<'PY'
import json, sys
faults = json.load(open(sys.argv[1], encoding="utf-8"))
result = json.load(open(sys.argv[2], encoding="utf-8"))
print(json.dumps(faults, indent=2))
if result.get("action") == "healed":
    if faults.get("latency_ms", 1) != 0 or float(faults.get("error_rate", 1)) != 0.0:
        raise SystemExit("FAIL: faults not reset after heal")
    print("OK: faults cleared")
else:
    print("Note: skipped heal — fault state may still reflect prior injection")
PY

if command -v kubectl >/dev/null 2>&1; then
  log "Wait for payments-mock rollout"
  kubectl -n reliable-app rollout status deploy/payments-mock --timeout=90s
  AFTER_RS="$(kubectl -n reliable-app get deploy/payments-mock \
    -o jsonpath='{.spec.template.metadata.annotations.reliable-app\.io/restartedAt}' 2>/dev/null || true)"
  log "payments-mock restartedAt (after): ${AFTER_RS:-<none>}"
  if [[ -n "${AFTER_RS}" && "${AFTER_RS}" != "${BEFORE_RS}" ]]; then
    log "OK: rollout restart annotation updated"
  else
    # skipped cooldown may leave annotation unchanged
    log "Note: annotation unchanged (cooldown skip or same stamp)"
  fi
fi

log "Done — Alertmanager also posts here on real P1 pages (see alertmanager.yml)"
