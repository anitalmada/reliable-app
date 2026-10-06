# RB_CIRCUIT_OPEN — Checkout payments circuit open

**Severity:** operational / follows payment outage  
**Brand:** [Con Alma Tech](https://conalma.tech)

## Symptom

`GET http://127.0.0.1:8082/circuit` shows `"state": "open"`.  
Pay returns **HTTP 503** with detail *Payment under maintenance…* instead of calling `payments-mock`.

Metric: `payments_circuit_open_total` on checkout-api.

## What this means

Checkout is **protecting itself**. Repeated payment failures tripped the breaker (`CB_FAILURE_THRESHOLD`, default 3). The app stays up in **degraded mode** instead of hanging on a dead dependency.

## Diagnose

```bash
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool
kubectl -n reliable-app logs deploy/checkout-api --tail=40
kubectl -n reliable-app logs deploy/payments-mock --tail=40
```

Reproduce intentionally:

```bash
./scripts/demo-circuit-breaker.sh
```

## Mitigate

1. Fix the dependency (clear faults / heal payments):

```bash
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'
```

2. Wait `CB_RECOVERY_TIMEOUT_S` (default 30s) for **half_open**, then one successful pay closes the circuit — or restart checkout for a clean closed state:

```bash
kubectl -n reliable-app rollout restart deploy/checkout-api
kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
```

3. If PAGE burn is also firing, follow [RB_ERR_BUDGET_BURN_FAST.md](RB_ERR_BUDGET_BURN_FAST.md).

## Related

- Docs: [../automation/circuit-breaker/README.md](../automation/circuit-breaker/README.md)
- ES: [RB_CIRCUIT_OPEN.es.md](RB_CIRCUIT_OPEN.es.md)
