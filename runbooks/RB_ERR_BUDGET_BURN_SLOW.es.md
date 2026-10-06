# RB_ERR_BUDGET_BURN_SLOW — TICKET: quema lenta de error budget

**Severidad:** ticket (P2)  
**Owner:** ingeniero en horario laboral  
**Marca:** [Con Alma Tech](https://conalma.tech)

## Alertas cubiertas

| Nombre | SLO |
|---|---|
| `ErrorBudgetBurnSlowAvailability` | availability |
| `ErrorBudgetBurnSlowPaymentLatency` | payment_latency |
| `ErrorBudgetBurnSlowCheckoutSuccess` | checkout_success |

Ruta: **alert-inbox** `/ticket` (sin page ni self-heal).

## Qué significa

El burn está elevado a ~**6×** en **6h** y **30m**, pero aún no pagina. Actuar en horario laboral antes de que se acelere a PAGE.

## Diagnosticar

```bash
./scripts/check-alerts.sh
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
./scripts/query-error-budget.sh
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool
```

Abrir **Executive** + **Triage** en http://127.0.0.1:3000.

## Mitigar

Normalmente **sin restart de emergencia**:

1. ¿Quedó fault injection activa? (`/admin/faults`)
2. Limpiar faults si no están en cero.
3. Si es regresión real: ticket con capturas de Grafana + salida de `query-error-budget.sh`.
4. Si acelera a PAGE → [RB_ERR_BUDGET_BURN_FAST.es.md](RB_ERR_BUDGET_BURN_FAST.es.md).

```bash
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'
```

## Relacionados

- PAGE: [RB_ERR_BUDGET_BURN_FAST.es.md](RB_ERR_BUDGET_BURN_FAST.es.md)
- EN: [RB_ERR_BUDGET_BURN_SLOW.md](RB_ERR_BUDGET_BURN_SLOW.md)
