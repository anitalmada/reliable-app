# RB_ERR_BUDGET_BURN_FAST — PAGE: quema rápida de error budget

**Severidad:** page (P1)  
**Owner:** on-call  
**Marca:** [Con Alma Tech](https://conalma.tech)

## Alertas cubiertas

| Nombre de alerta | SLO |
|---|---|
| `ErrorBudgetBurnFastAvailability` | Disponibilidad HTTP (99.5%) |
| `ErrorBudgetBurnFastPaymentLatency` | Latencia de pago (p95 &lt; 500ms para el 95%) |
| `ErrorBudgetBurnFastCheckoutSuccess` | Éxito de pay en checkout (99.9%) |

Alertmanager las enruta a **alert-inbox** `/pager` y **self-heal** `/webhook`.

## Qué significa (impacto de negocio)

Estamos quemando el error budget de 30 días a ~**14.4×** en las ventanas de **1h** y **5m**. A ese ritmo el presupuesto del mes se agota en horas, no en días.

| SLO | Impacto visible |
|---|---|
| Disponibilidad | 5xx / rutas caídas |
| Latencia de pago | Checkout trabado; abandono en el pago |
| Éxito de checkout | Cobros fallidos; pérdida de revenue |

## Diagnosticar (primeros 2 minutos)

### 1. Confirmar la alerta

```bash
./scripts/check-alerts.sh
curl -s http://127.0.0.1:9090/api/v1/alerts | python3 -m json.tool | head
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
```

### 2. Dashboards

| Dashboard | URL |
|---|---|
| Executive (semáforos de budget) | http://127.0.0.1:3000 |
| Triage (golden signals) | http://127.0.0.1:3000 |
| Alertmanager | http://127.0.0.1:9093 |

### 3. Fallos inyectados / salud de dependencias

```bash
curl -s http://127.0.0.1:8083/admin/faults | python3 -m json.tool
kubectl -n reliable-app get pods
kubectl -n reliable-app logs deploy/payments-mock --tail=50
kubectl -n reliable-app logs deploy/checkout-api --tail=50
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
```

### 4. Números de budget

```bash
./scripts/query-error-budget.sh
```

## Mitigación automática (self-heal)

En PAGE, Alertmanager también llama a `self-heal`, que:

1. Escribe evidencia stub en `/evidence`
2. Resetea los faults de `payments-mock`
3. Hace rollout restart de Deployment `payments-mock`

```bash
curl -s http://127.0.0.1:8085/actions | python3 -m json.tool
curl -s http://127.0.0.1:8085/evidence | python3 -m json.tool
```

Si `action=healed` y los faults están en cero, espera ~1–2 min a que las ventanas se enfríen; no generes más tráfico malo.

## Mitigar a mano (si falla self-heal)

```bash
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'

kubectl -n reliable-app rollout restart deploy/payments-mock
kubectl -n reliable-app rollout status deploy/payments-mock --timeout=90s

curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
kubectl -n reliable-app rollout restart deploy/checkout-api
kubectl -n reliable-app rollout status deploy/checkout-api --timeout=90s

./scripts/smoke-test.sh
```

Forzar webhook de heal (demo):

```bash
./scripts/demo-self-heal.sh
```

## Verificar recuperación

- [ ] `./scripts/check-alerts.sh` — PAGE ya no firing (o resolviendo)
- [ ] `/admin/faults` en ceros
- [ ] `GET /circuit` en `closed` (o recupera tras probe)
- [ ] Dashboard Executive subiendo
- [ ] Inbox sin flood de pager nuevo

## Relacionados

- Quema lenta (ticket): [RB_ERR_BUDGET_BURN_SLOW.es.md](RB_ERR_BUDGET_BURN_SLOW.es.md)
- Circuit abierto: [RB_CIRCUIT_OPEN.es.md](RB_CIRCUIT_OPEN.es.md)
- EN: [RB_ERR_BUDGET_BURN_FAST.md](RB_ERR_BUDGET_BURN_FAST.md)
- Guion de transferencia: [../docs/TRANSFER_VIDEO.md](../docs/TRANSFER_VIDEO.md)
