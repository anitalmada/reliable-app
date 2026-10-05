# Definición de SLOs — Reliable App

Objetivos de nivel de servicio orientados al negocio para el demo e-commerce  
(**Con Alma Tech** · [conalma.tech](https://conalma.tech)).

English: [SLO_DEFINITION.md](SLO_DEFINITION.md)

Este documento define **qué prometemos**, no cómo se ven los dashboards.  
Las recording rules de Prometheus están en `infra/k8s/base/prometheus/recording_rules.yml`.

---

## Servicios en alcance

| Servicio | Journey crítico |
|---|---|
| `catalog-api` | Explorar productos |
| `checkout-api` | Crear checkout y completar el pago |
| `payments-mock` | Cobro (procesador simulado) |

Camino de dinero: **listar → checkout → pagar**.

---

## SLIs y SLOs

### 1. Disponibilidad (éxito HTTP)

| | |
|---|---|
| **SLI** | Porcentaje de requests HTTP válidas que tienen éxito (`2xx` / `3xx`). Los errores de cliente (`4xx`) se excluyen del denominador. |
| **Alcance** | Las tres APIs (`job` = `catalog-api`, `checkout-api`, `payments-mock`), excluyendo `/health` y `/metrics`. |
| **SLO** | **99.5%** en ventana móvil de **30 días** |
| **Ratio de fallo permitido** | `0.5%` (`1 - 0.995`) |

### 2. Latencia de pagos

| | |
|---|---|
| **SLI** | Porcentaje de `POST /charge` en `payments-mock` completadas en **&lt; 500 ms**. |
| **SLO** | **95%** en **30 días** |
| **Ratio de incumplimiento permitido** | `5%` (`1 - 0.95`) |

### 3. Éxito crítico de checkout (sin 5xx en el pago)

| | |
|---|---|
| **SLI** | Porcentaje de **intentos de pago** de checkout que terminan en éxito (contador `checkout_total{status="completed"}` vs `completed|failed`). |
| **SLO** | **99.9%** en **30 días** |
| **Ratio de fallo permitido** | `0.1%` (`1 - 0.999`) |

---

## Error budget (presupuesto de error)

```text
error_budget_remaining =
  1 - (observed_bad_ratio / allowed_bad_ratio)
```

Acotado a `[0, 1]` en dashboards / CI.

| SLO | Malo permitido | Recording rule |
|---|---|---|
| Disponibilidad 99.5% | 0.005 | `slo:error_budget_remaining:ratio{slo="availability"}` |
| Latencia de pago 95% | 0.05 | `slo:error_budget_remaining:ratio{slo="payment_latency"}` |
| Éxito de checkout 99.9% | 0.001 | `slo:error_budget_remaining:ratio{slo="checkout_success"}` |

### Demo local vs producción

| Entorno | Cómo se calculan los SLIs | Por qué |
|---|---|---|
| **Demo Kind** | Ratios sobre contadores acumulados (recording rules) | Con poco tráfico, `rate([1h])` tiende a cero |
| **Intención de producción** | `rate(...[30d])` / `increase(...[30d])` | Coincide con la ventana de 30 días |

Los **objetivos** (99.5% / 95% / 99.9%) no cambian.

```bash
./scripts/query-error-budget.sh
```

---

## Política de freeze de deploys

**Regla:** si **cualquier** SLO crítico tiene `error_budget_remaining < 20%` en la ventana de evaluación, **congelar deploys de features** hasta recuperar presupuesto o aprobar una excepción explícita.

| Budget restante | Acción |
|---|---|
| ≥ 50% | Deploys normales |
| 20% – 50% | Priorizar fiabilidad; features con revisión extra |
| &lt; 20% | **Freeze** de features; solo cambios de reliability |
| 0% | Incident / presupuesto agotado — stop the line |

```bash
./scripts/check-error-budget.sh --min-remaining 0.20
```

---

## Cómo ejercitar los SLIs en local

```bash
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh

# Quemar budget de latencia (delay 2s)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0,"timeout":false}'

# O quemar budget de éxito de checkout (100% 5xx)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}'

./scripts/query-error-budget.sh
```

UI de Prometheus: http://127.0.0.1:9090
