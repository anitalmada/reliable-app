# Circuit breaker (checkout → payments)

The circuit breaker lives **in** `checkout-api` (`app/checkout-api/circuit_breaker.py`),
not as a separate Envoy sidecar — enough to demo the resilience pattern.

## Behaviour

```text
CLOSED ──(N payment failures)──► OPEN ──(cooldown)──► HALF_OPEN
   ▲                                                    │
   └────────────(probe success)─────────────────────────┘
```

| State | Pay behaviour |
|---|---|
| `closed` | Call `payments-mock` `/charge` as usual |
| `open` | **Do not call** payments; HTTP **503** + status `degraded` (“payment under maintenance…”) |
| `half_open` | Allow one probe call after `CB_RECOVERY_TIMEOUT_S` |

Defaults: `CB_FAILURE_THRESHOLD=3`, `CB_RECOVERY_TIMEOUT_S=30`.

## Why this matters for SRE demos

- Payment outages **do not cascade** into unbounded checkout latency / thread exhaustion.
- Users get a **degraded** response instead of a hanging app.
- Pairs with Phase 3 burn-rate alerts and Phase 4 self-heal (restart + clear faults).

## Try it

```bash
# Force payment 5xx
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}'

# Fail pays until circuit opens (3×)
# then next pay returns 503 degraded without hitting payments

curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
```

Or: `./scripts/demo-circuit-breaker.sh`
