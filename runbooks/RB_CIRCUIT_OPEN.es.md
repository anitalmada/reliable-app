# RB_CIRCUIT_OPEN — Circuit de pagos abierto en checkout

**Severidad:** operacional / sigue a una outage de pagos  
**Marca:** [Con Alma Tech](https://conalma.tech)

## Síntoma

`GET http://127.0.0.1:8082/circuit` muestra `"state": "open"`.  
Pay responde **HTTP 503** con *Payment under maintenance…* sin llamar a `payments-mock`.

Métrica: `payments_circuit_open_total` en checkout-api.

## Qué significa

Checkout se **protege**. Fallos repetidos de pago abrieron el breaker (`CB_FAILURE_THRESHOLD`, default 3). La app sigue arriba en modo **degraded** en lugar de colgarse en una dependencia muerta.

## Diagnosticar

```bash
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool
kubectl -n reliable-app logs deploy/checkout-api --tail=40
kubectl -n reliable-app logs deploy/payments-mock --tail=40
```

Reproducir:

```bash
./scripts/demo-circuit-breaker.sh
```

## Mitigar

1. Arreglar la dependencia (limpiar faults / heal payments).
2. Esperar `CB_RECOVERY_TIMEOUT_S` (30s) para **half_open** + un pay OK, o reiniciar checkout:

```bash
kubectl -n reliable-app rollout restart deploy/checkout-api
kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s
```

3. Si también hay PAGE burn → [RB_ERR_BUDGET_BURN_FAST.es.md](RB_ERR_BUDGET_BURN_FAST.es.md).

## Relacionados

- Docs: [../automation/circuit-breaker/README.md](../automation/circuit-breaker/README.md)
- EN: [RB_CIRCUIT_OPEN.md](RB_CIRCUIT_OPEN.md)
