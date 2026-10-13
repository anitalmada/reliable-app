# SLO Definition — Reliable App

Business-focused service level objectives for the demo e-commerce stack  
(**Con Alma Tech** · [conalma.tech](https://conalma.tech)).

Spanish: [SLO_DEFINITION.es.md](SLO_DEFINITION.es.md)

This document defines **what we promise**, not how dashboards look.  
Prometheus recording rules that compute these numbers live in  
`infra/k8s/base/prometheus/recording_rules.yml`.

---

## Services in scope

| Service | Critical user journey |
|---|---|
| `catalog-api` | Browse products |
| `checkout-api` | Create checkout and complete payment |
| `payments-mock` | Charge (simulated payment processor) |

Primary money path: **list → checkout → pay**.

---

## SLIs and SLOs

### 1. Availability (HTTP success)

| | |
|---|---|
| **SLI** | Percentage of valid HTTP requests that succeed (`2xx` / `3xx`). Client errors (`4xx`) are excluded from the denominator. |
| **Scope** | All three APIs (`job` = `catalog-api`, `checkout-api`, `payments-mock`), excluding `/health` and `/metrics`. |
| **SLO** | **99.5%** over a **30-day** rolling window |
| **Allowed failure ratio** | `0.5%` (`1 - 0.995`) |

**PromQL (ratio of good events):** see recording rule `sli:http_availability:ratio`.

### 2. Payment latency

| | |
|---|---|
| **SLI** | Percentage of `POST /charge` requests on `payments-mock` completed in **&lt; 500 ms**. |
| **SLO** | **95%** over a **30-day** rolling window |
| **Allowed miss ratio** | `5%` (`1 - 0.95`) |

**PromQL:** recording rule `sli:payment_latency:ratio` (histogram bucket `le="0.5"`).

### 3. Critical checkout success (no 5xx on pay)

| | |
|---|---|
| **SLI** | Percentage of checkout **payment attempts** that complete successfully (business counter `checkout_total{status="completed"}` vs `completed|failed`). |
| **SLO** | **99.9%** over a **30-day** rolling window |
| **Allowed failure ratio** | `0.1%` (`1 - 0.999`) |

**PromQL:** recording rule `sli:checkout_success:ratio`.

---

## Error budget

For each SLO:

```text
error_budget_remaining =
  1 - (observed_bad_ratio / allowed_bad_ratio)
```

Clamped to `[0, 1]` in dashboards / CI.

| SLO | Allowed bad ratio | Recording rule |
|---|---|---|
| Availability 99.5% | 0.005 | `slo:error_budget_remaining:ratio{slo="availability"}` |
| Payment latency 95% | 0.05 | `slo:error_budget_remaining:ratio{slo="payment_latency"}` |
| Checkout success 99.9% | 0.001 | `slo:error_budget_remaining:ratio{slo="checkout_success"}` |

### Local demo vs production window

| Environment | How SLIs are computed | Why |
|---|---|---|
| **Kind demo** | `increase(...[1h])` windows (+ `or vector(0)` when no traffic) | Executive budgets recover after healthy traffic; empty `/charge` after pod restart is not “No data” |
| **Production intent** | `rate(...[30d])` / `increase(...[30d])` | Matches the 30-day SLO window |

**Production-style examples** (same targets; swap into rules when you have retention + steady traffic):

```promql
# Availability (30d)
sum(rate(http_requests_total{status=~"2..|3.."}[30d]))
/
sum(rate(http_requests_total{status!~"4.."}[30d]))
```

The **targets** (99.5% / 95% / 99.9%) stay the same. Only the measurement method differs for the lab.

Query remaining budget in Prometheus UI or:

```bash
./scripts/query-error-budget.sh
```

---

## Deploy freeze policy

**Rule:** if **any** critical SLO has `error_budget_remaining < 20%` on the evaluation window, **freeze feature deploys** until the budget recovers or an explicit exception is approved.

| Budget remaining | Action |
|---|---|---|
| ≥ 50% | Normal deploys |
| 20% – 50% | Prefer fixes / reliability work; feature deploys need extra review |
| &lt; 20% | **Freeze** feature deploys; reliability-only changes |
| 0% | Incident / error-budget exhaustion — stop the line |

CI sketch (fail the pipeline when budget is too low):

```bash
# Example gate — used by scripts/check-error-budget.sh
./scripts/check-error-budget.sh --min-remaining 0.20
```

This gate is the “policy as code” counterpart to the PromQL rules. Wire it into GitHub Actions / GitLab CI when you add continuous delivery.

---

## How to exercise the SLIs locally

```bash
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh

# Burn payment latency budget (2s delay)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":2000,"error_rate":0,"timeout":false}'

# Or burn checkout success budget (100% 5xx)
curl -s -X POST http://127.0.0.1:8083/admin/faults \
  -H 'Content-Type: application/json' \
  -d '{"latency_ms":0,"error_rate":1.0,"timeout":false}'

./scripts/query-error-budget.sh
```

Prometheus UI: http://127.0.0.1:9090
