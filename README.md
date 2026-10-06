# Reliable App

Minimal e-commerce demo for **[Con Alma Tech](https://conalma.tech)** SRE service packages.

Three FastAPI services on local **Kind**, with injectable payment faults and Prometheus `/metrics` on each API — enough to show the **four golden signals** and later SLOs.

| Service | Local URL | Role |
|---|---|---|
| `catalog-api` | http://127.0.0.1:8081 | Product list / detail |
| `checkout-api` | http://127.0.0.1:8082 | Checkout + pay orchestration |
| `payments-mock` | http://127.0.0.1:8083 | Mock payments + fault injection |
| Prometheus | http://127.0.0.1:9090 | Metrics + SLI recording rules |
| Grafana | http://127.0.0.1:3000 | Dashboards as code (`admin` / `admin`) |
| Alertmanager | http://127.0.0.1:9093 | Routes P1 (page) vs P2 (ticket) |
| alert-inbox | http://127.0.0.1:8084 | Demo webhook sink for P1/P2 |
| self-heal | http://127.0.0.1:8085 | P1 mitigation (restart + clear faults) |

**Who it’s for:** teams evaluating SRE demos (latency, errors, saturation) without a full production stack.

**Languages:** English (this file) · [Español](README.es.md)  
**Repos:** [GitHub](https://github.com/anitalmada/reliable-app) (EN) · [GitLab](https://gitlab.com/anitalmada/reliable-app) (ES, canonical)

---

## Prerequisites

- Docker (daemon running)
- `curl` and `python3` (for the smoke test)
- `kind` and `kubectl` — installed automatically by the bootstrap script into `~/.local/bin` if missing

## Bring up (~10 min)

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh
# wait ~30s for scrape + recording rules, then:
./scripts/query-error-budget.sh
```

OpenAPI docs: `/docs` on each port above.

## Happy path

```bash
# Products
curl -s http://127.0.0.1:8081/products | python3 -m json.tool

# Checkout
curl -s -X POST http://127.0.0.1:8082/checkout \
  -H 'Content-Type: application/json' \
  -d '{"items":[{"product_id":1,"quantity":1,"unit_price_cents":1500}],"total_cents":1500,"currency":"USD"}'

# Pay (replace CHECKOUT_ID)
curl -s -X POST http://127.0.0.1:8082/checkout/CHECKOUT_ID/pay
```

## Fault injection (payments-mock)

Change behavior via API — no redeploy:

```bash
# 100% 5xx on /charge
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}'

# High latency (ms)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0,"timeout":false}'

# Reset
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":0,"timeout":false}'
```

## SLOs and error budget

See [SLO_DEFINITION.md](SLO_DEFINITION.md) (business SLIs, freeze policy).

| | URL / command |
|---|---|
| Prometheus UI | http://127.0.0.1:9090 |
| Remaining budget | `./scripts/query-error-budget.sh` |
| Deploy freeze gate | `./scripts/check-error-budget.sh --min-remaining 0.20` |

PromQL series: `slo:error_budget_remaining:ratio` (labels `slo=availability|payment_latency|checkout_success`).

## Grafana (dashboards as code)

Open http://127.0.0.1:3000 (anonymous Viewer, or `admin` / `admin`).

Dashboards load from git — no manual import:

| Dashboard | Purpose |
|---|---|
| **Executive** | SLO error-budget traffic lights + trends |
| **Triage** | Four golden signals (latency, traffic, errors, saturation) |
| **Infra** | Process CPU / memory / FDs per service |

JSON + provisioning: `infra/k8s/base/grafana/`.

If a new port does not respond (Kind maps are fixed at cluster create):

```bash
kind delete cluster --name reliable-app && ./scripts/bootstrap-kind.sh
```

## Alerts (error-budget burn rate)

No CPU thresholds. Alerts use **multi-window multi-burn-rate** on SLOs:

| Severity | Windows | Factor | Route |
|---|---|---|---|
| **page** (P1) | 1h + 5m | 14.4× | `alert-inbox` `/pager` |
| **ticket** (P2) | 6h + 30m | 6× | `alert-inbox` `/ticket` |

Rules: `infra/k8s/base/prometheus/alert_rules.yml`  
Routing: `infra/k8s/base/alertmanager/alertmanager.yml`

```bash
# Demo: inject latency until PAGE alert fires (~3–4 min)
./scripts/demo-latency-alert.sh
./scripts/check-alerts.sh
curl -s http://127.0.0.1:8084/inbox | python3 -m json.tool
```

## Resilience (circuit breaker + self-heal)

Payment outages should not cascade. Checkout opens a **circuit breaker** after repeated failures and returns **503 degraded**. Alertmanager P1 pages also hit a **self-heal** webhook that writes evidence, clears payment faults, and rollouts `payments-mock`.

| | Command / docs |
|---|---|
| Circuit demo | `./scripts/demo-circuit-breaker.sh` |
| Self-heal demo | `./scripts/demo-self-heal.sh` |
| Circuit docs | [automation/circuit-breaker/README.md](automation/circuit-breaker/README.md) |
| Self-heal docs | [automation/self-heal/README.md](automation/self-heal/README.md) |

```bash
curl -s http://127.0.0.1:8082/circuit | python3 -m json.tool
curl -s http://127.0.0.1:8085/actions | python3 -m json.tool
```

## Tear down

```bash
kind delete cluster --name reliable-app
```

## Layout

```text
app/                 FastAPI services (catalog, checkout, payments-mock)
infra/k8s/           Kind config + Kustomize (APIs, Prometheus, Grafana)
infra/k8s/base/prometheus/  scrape + recording rules (SLIs / error budget)
infra/k8s/base/grafana/     dashboards JSON + provisioning
SLO_DEFINITION.md    Business SLOs (EN) · SLO_DEFINITION.es.md (ES)
scripts/             bootstrap, smoke-test, query/check error budget
automation/          self-heal webhook + circuit-breaker docs
runbooks/            incident guides (later)
```

---

Built by **[Con Alma Tech](https://conalma.tech)** — SRE with a human touch.
