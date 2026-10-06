# Reliable App

Demo mínimo de e-commerce para los paquetes SRE de **[Con Alma Tech](https://conalma.tech)**.

Tres servicios FastAPI en **Kind** local, con fallos inyectables en pagos y `/metrics` Prometheus en cada API — base para las **cuatro señales doradas** y, más adelante, SLOs.

| Servicio | URL local | Rol |
|---|---|---|
| `catalog-api` | http://127.0.0.1:8081 | Listado / detalle de productos |
| `checkout-api` | http://127.0.0.1:8082 | Checkout + orquestación de pago |
| `payments-mock` | http://127.0.0.1:8083 | Pagos mock + inyección de fallos |
| Prometheus | http://127.0.0.1:9090 | Métricas + recording rules de SLI |
| Grafana | http://127.0.0.1:3000 | Dashboards as code (`admin` / `admin`) |
| Alertmanager | http://127.0.0.1:9093 | Rutas P1 (página) vs P2 (ticket) |
| alert-inbox | http://127.0.0.1:8084 | Sink demo de webhooks P1/P2 |
| self-heal | http://127.0.0.1:8085 | Mitigación P1 (restart + limpiar fallos) |

**Para quién:** equipos que evalúan demos SRE (latencia, errores, saturación) sin un stack de producción completo.

**Idiomas:** [English](README.md) · Español (este archivo)  
**Repos:** [GitLab](https://gitlab.com/anitalmada/reliable-app) (ES, canónico) · [GitHub](https://github.com/anitalmada/reliable-app) (EN)

---

## Requisitos

- Docker (daemon en ejecución)
- `curl` y `python3` (para el smoke test)
- `kind` y `kubectl` — el script de bootstrap los instala en `~/.local/bin` si faltan

## Levantar el entorno (~10 min)

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh
# esperar ~30s para scrape + recording rules, luego:
./scripts/query-error-budget.sh
```

Documentación OpenAPI: `/docs` en cada puerto de la tabla.

## Camino feliz

```bash
# Productos
curl -s http://127.0.0.1:8081/products | python3 -m json.tool

# Checkout
curl -s -X POST http://127.0.0.1:8082/checkout \
  -H 'Content-Type: application/json' \
  -d '{"items":[{"product_id":1,"quantity":1,"unit_price_cents":1500}],"total_cents":1500,"currency":"USD"}'

# Pagar (reemplazar CHECKOUT_ID)
curl -s -X POST http://127.0.0.1:8082/checkout/CHECKOUT_ID/pay
```

## Inyección de fallos (payments-mock)

Cambiar el comportamiento por API — sin redesplegar:

```bash
# 100% de 5xx en /charge
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}'

# Alta latencia (ms)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0,"timeout":false}'

# Reset
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'
```

## SLOs y error budget

Ver [SLO_DEFINITION.es.md](SLO_DEFINITION.es.md) (SLIs de negocio, política de freeze).

| | URL / comando |
|---|---|
| UI de Prometheus | http://127.0.0.1:9090 |
| Budget restante | `./scripts/query-error-budget.sh` |
| Gate de freeze | `./scripts/check-error-budget.sh --min-remaining 0.20` |

Serie PromQL: `slo:error_budget_remaining:ratio` (labels `slo=availability|payment_latency|checkout_success`).

## Grafana (dashboards as code)

Abrí http://127.0.0.1:3000 (Viewer anónimo, o `admin` / `admin`).

Los dashboards cargan desde git — sin importar a mano:

| Dashboard | Propósito |
|---|---|
| **Executive** | Semáforos de error budget + tendencias |
| **Triage** | Cuatro señales doradas |
| **Infra** | CPU / memoria / FDs de proceso por servicio |

JSON + provisioning: `infra/k8s/base/grafana/`.

Si un puerto nuevo no responde (los maps de Kind se fijan al crear el cluster):

```bash
kind delete cluster --name reliable-app && ./scripts/bootstrap-kind.sh
```

## Alertas (burn rate de error budget)

Sin umbrales de CPU. Alertas **multi-window multi-burn-rate** sobre SLOs:

| Severidad | Ventanas | Factor | Ruta |
|---|---|---|---|
| **page** (P1) | 1h + 5m | 14.4× | `alert-inbox` `/pager` |
| **ticket** (P2) | 6h + 30m | 6× | `alert-inbox` `/ticket` |

```bash
./scripts/demo-latency-alert.sh
./scripts/check-alerts.sh
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
```

## Resiliencia (circuit breaker + self-heal)

Los fallos de pago no deben propagarse al resto del checkout. Checkout abre un **circuit breaker** tras fallos repetidos y responde **503 degraded**. Las páginas P1 de Alertmanager también llegan a un webhook **self-heal** que escribe evidencia, limpia fallos de pagos y hace rollout de `payments-mock`.

| | Comando / docs |
|---|---|
| Demo circuit | `./scripts/demo-circuit-breaker.sh` |
| Demo self-heal | `./scripts/demo-self-heal.sh` |
| Docs circuit | [automation/circuit-breaker/README.md](automation/circuit-breaker/README.md) |
| Docs self-heal | [automation/self-heal/README.md](automation/self-heal/README.md) |

```bash
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
curl -s http://127.0.0.1:8085/actions | python3 -m json.tool
```

## Apagar

```bash
kind delete cluster --name reliable-app
```

## Estructura

```text
app/                 Servicios FastAPI (catalog, checkout, payments-mock)
infra/k8s/           Config Kind + Kustomize (APIs, Prometheus, Grafana)
infra/k8s/base/prometheus/  scrape + recording rules (SLIs / error budget)
infra/k8s/base/grafana/     dashboards JSON + provisioning
SLO_DEFINITION.es.md SLOs de negocio (ES) · SLO_DEFINITION.md (EN)
scripts/             bootstrap, smoke-test, query/check error budget
automation/          webhook self-heal + docs del circuit breaker
runbooks/            guías de incidente (más adelante)
```

---

Hecho por **[Con Alma Tech](https://conalma.tech)** — SRE con toque humano.
