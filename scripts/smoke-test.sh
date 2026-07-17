#!/usr/bin/env bash
# Happy-path + fault-injection smoke test against local Kind NodePorts.
set -euo pipefail

CATALOG="${CATALOG_URL:-http://127.0.0.1:8081}"
CHECKOUT="${CHECKOUT_URL:-http://127.0.0.1:8082}"
PAYMENTS="${PAYMENTS_URL:-http://127.0.0.1:8083}"

log() { printf '==> %s\n' "$*"; }

log "Health checks"
curl -fsS "${CATALOG}/health"
echo
curl -fsS "${CHECKOUT}/health"
echo
curl -fsS "${PAYMENTS}/health"
echo

log "Reset payments faults"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

log "List products"
curl -fsS "${CATALOG}/products" | tee /tmp/reliable-products.json
echo

PRODUCT_ID="$(python3 -c 'import json; print(json.load(open("/tmp/reliable-products.json"))[0]["id"])')"
PRICE="$(python3 -c 'import json; print(json.load(open("/tmp/reliable-products.json"))[0]["price_cents"])')"

log "Create checkout (product ${PRODUCT_ID})"
curl -fsS -X POST "${CHECKOUT}/checkout" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"product_id\":${PRODUCT_ID},\"quantity\":1,\"unit_price_cents\":${PRICE}}],\"total_cents\":${PRICE},\"currency\":\"USD\"}" \
  | tee /tmp/reliable-checkout.json
echo

CHECKOUT_ID="$(python3 -c 'import json; print(json.load(open("/tmp/reliable-checkout.json"))["id"])')"

log "Pay checkout ${CHECKOUT_ID}"
curl -fsS -X POST "${CHECKOUT}/checkout/${CHECKOUT_ID}/pay" | tee /tmp/reliable-paid.json
echo

STATUS="$(python3 -c 'import json; print(json.load(open("/tmp/reliable-paid.json"))["status"])')"
test "${STATUS}" = "completed" || { echo "Expected completed, got ${STATUS}" >&2; exit 1; }

log "Inject 100% payment errors"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}' >/dev/null

log "Create second checkout (expect pay failure)"
curl -fsS -X POST "${CHECKOUT}/checkout" \
  -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"product_id\":${PRODUCT_ID},\"quantity\":1,\"unit_price_cents\":${PRICE}}],\"total_cents\":${PRICE},\"currency\":\"USD\"}" \
  | tee /tmp/reliable-checkout2.json
echo
CHECKOUT_ID2="$(python3 -c 'import json; print(json.load(open("/tmp/reliable-checkout2.json"))["id"])')"

set +e
HTTP_CODE="$(curl -sS -o /tmp/reliable-pay-fail.json -w '%{http_code}' \
  -X POST "${CHECKOUT}/checkout/${CHECKOUT_ID2}/pay")"
set -e
echo "pay HTTP ${HTTP_CODE}"
test "${HTTP_CODE}" = "502" || { echo "Expected HTTP 502 from failed pay" >&2; exit 1; }

log "Reset faults"
curl -fsS -X POST "${PAYMENTS}/admin/faults" \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}' >/dev/null

log "Smoke test OK"
