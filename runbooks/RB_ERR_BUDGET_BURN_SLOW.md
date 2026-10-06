# RB_ERR_BUDGET_BURN_SLOW — TICKET: slow error-budget burn

**Severity:** ticket (P2)  
**Owner:** business-hours engineer  
**Brand:** [Con Alma Tech](https://conalma.tech)

## Alerts covered

| Alert name | SLO |
|---|---|
| `ErrorBudgetBurnSlowAvailability` | availability |
| `ErrorBudgetBurnSlowPaymentLatency` | payment_latency |
| `ErrorBudgetBurnSlowCheckoutSuccess` | checkout_success |

Routed to **alert-inbox** `/ticket` only (no page, no self-heal).

## What this means

Budget burn is elevated at ~**6×** over **6h** and **30m**, but not fast enough to page. Act in business hours before it accelerates into a PAGE.

## Diagnose

```bash
./scripts/check-alerts.sh
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
./scripts/query-error-budget.sh
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool
```

Open **Executive** + **Triage** at http://127.0.0.1:3000 and note which SLO is red/amber.

## Mitigate

Usually **no emergency restart**. Prefer:

1. Identify whether demo fault injection was left on (`/admin/faults`).
2. Clear faults if they are non-zero.
3. If a real regression, open a ticket with Grafana screenshots + `query-error-budget.sh` output.
4. If burn accelerates into PAGE → follow [RB_ERR_BUDGET_BURN_FAST.md](RB_ERR_BUDGET_BURN_FAST.md).

```bash
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'
```

## Related

- PAGE: [RB_ERR_BUDGET_BURN_FAST.md](RB_ERR_BUDGET_BURN_FAST.md)
- ES: [RB_ERR_BUDGET_BURN_SLOW.es.md](RB_ERR_BUDGET_BURN_SLOW.es.md)
