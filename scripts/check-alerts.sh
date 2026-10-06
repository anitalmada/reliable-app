#!/usr/bin/env bash
# Show firing Prometheus alerts and alert-inbox P1/P2 queues.
set -euo pipefail

PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
AM_URL="${AM_URL:-http://127.0.0.1:9093}"
INBOX_URL="${INBOX_URL:-http://127.0.0.1:8084}"
TMPDIR="${TMPDIR:-/tmp}"

log() { printf '==> %s\n' "$*"; }

log "Prometheus firing alerts"
curl -fsS --get "${PROM_URL}/api/v1/alerts" -o "${TMPDIR}/reliable-prom-alerts.json"
python3 - "${TMPDIR}/reliable-prom-alerts.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
alerts = data.get("data", {}).get("alerts", [])
firing = [a for a in alerts if a.get("state") == "firing"]
if not firing:
    print("(none firing)")
for a in firing:
    labels = a.get("labels", {})
    print(
        f"- {labels.get('alertname')} severity={labels.get('severity')} "
        f"slo={labels.get('slo')} state={a.get('state')}"
    )
    print(f"  {a.get('annotations', {}).get('summary', '')}")
PY

log "Alertmanager alerts"
curl -fsS "${AM_URL}/api/v2/alerts" -o "${TMPDIR}/reliable-am-alerts.json"
python3 - "${TMPDIR}/reliable-am-alerts.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    alerts = json.load(f)
if not alerts:
    print("(none)")
for a in alerts:
    labels = a.get("labels", {})
    print(
        f"- {labels.get('alertname')} severity={labels.get('severity')} "
        f"slo={labels.get('slo')} status={a.get('status', {}).get('state')}"
    )
PY

log "alert-inbox queues (P1=/pager P2=/ticket)"
curl -fsS "${INBOX_URL}/inbox" | python3 -m json.tool
