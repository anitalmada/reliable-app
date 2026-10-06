# RB_ERR_BUDGET_BURN_FAST — PAGE: fast error-budget burn

**Severity:** page (P1)  
**Owner:** on-call  
**Brand:** [Con Alma Tech](https://conalma.tech)

## Alerts covered

| Alert name | SLO |
|---|---|
| `ErrorBudgetBurnFastAvailability` | HTTP availability (99.5%) |
| `ErrorBudgetBurnFastPaymentLatency` | Payment latency (p95 &lt; 500ms for 95%) |
| `ErrorBudgetBurnFastCheckoutSuccess` | Checkout pay success (99.9%) |

Alertmanager routes these to **alert-inbox** `/pager` and **self-heal** `/webhook`.

## What this means (business impact)

We are burning the 30-day error budget at ~**14.4×** on both the **1h** and **5m** windows. At this rate the month’s budget is gone in hours, not days.

| SLO | User-visible impact |
|---|---|
| Availability | API 5xx / unreachable paths |
| Payment latency | Checkout feels stuck; users abandon pay |
| Checkout success | Failed charges; lost revenue |

## Diagnose (first 2 minutes)

### 1. Confirm the alert

```bash
./scripts/check-alerts.sh
curl -s http://127.0.0.1:9090/api/v1/alerts | python3 -m json.tool | head
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
```

### 2. Dashboards

| Dashboard | URL |
|---|---|
| Executive (budget traffic lights) | http://127.0.0.1:3000 |
| Triage (golden signals) | http://127.0.0.1:3000 |
| Alertmanager | http://127.0.0.1:9093 |

### 3. Fault injection / dependency health

```bash
# Is chaos still on?
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool

# Pods
kubectl -n reliable-app get pods
kubectl -n reliable-app logs deploy/payments-mock --tail=50
kubectl -n reliable-app logs deploy/checkout-api --tail=50

# Circuit state (checkout may already be protecting itself)
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
```

### 4. Budget numbers

```bash
./scripts/query-error-budget.sh
```

## Automatic mitigation (self-heal)

On PAGE, Alertmanager also calls `self-heal`, which:

1. Writes an evidence stub under `/evidence`
2. Resets `payments-mock` faults to healthy
3. Rollout-restarts Deployment `payments-mock`

```bash
curl -s http://127.0.0.1:8085/actions | python3 -m json.tool
curl -s http://127.0.0.1:8085/evidence | python3 -m json.tool
```

If `action=healed` and faults are zero, wait ~1–2 minutes for burn windows to cool; do not keep generating bad traffic.

## Manual mitigate (if self-heal fails or cooldown skipped)

```bash
# 1. Clear payment faults
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'

# 2. Restart the payment dependency
kubectl -n reliable-app rollout restart deploy/payments-mock
kubectl -n reliable-app rollout status deploy/payments-mock --timeout=90s

# 3. If checkout circuit is OPEN, restart checkout after payments are healthy
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
kubectl -n reliable-app rollout restart deploy/checkout-api
kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s

# 4. Verify a happy-path pay
./scripts/smoke-test.sh
```

Force a heal webhook (demo / stuck cooldown after you fixed root cause):

```bash
./scripts/demo-self-heal.sh
```

## Verify recovery

- [ ] `./scripts/check-alerts.sh` — PAGE no longer firing (or pending resolve)
- [ ] `/admin/faults` shows zeros
- [ ] `GET /circuit` is `closed` (or recovers after probe)
- [ ] Executive dashboard budgets trending up
- [ ] Inbox shows resolved or no new pager floods

## Related

- Slow burn (ticket): [RB_ERR_BUDGET_BURN_SLOW.md](RB_ERR_BUDGET_BURN_SLOW.md)
- Circuit / degraded mode: [RB_CIRCUIT_OPEN.md](RB_CIRCUIT_OPEN.md)
- ES: [RB_ERR_BUDGET_BURN_FAST.es.md](RB_ERR_BUDGET_BURN_FAST.es.md)
- Transfer outline: [../docs/TRANSFER_VIDEO.md](../docs/TRANSFER_VIDEO.md)
