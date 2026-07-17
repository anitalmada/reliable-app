# Reliable App

Minimal e-commerce demo for **[Con Alma Tech](https://conalma.tech)** SRE service packages.

Three FastAPI services on local **Kind**, with injectable payment faults and Prometheus `/metrics` on each API — enough to show the **four golden signals** and later SLOs.

| Service | Local URL | Role |
|---|---|---|
| `catalog-api` | http://127.0.0.1:8081 | Product list / detail |
| `checkout-api` | http://127.0.0.1:8082 | Checkout + pay orchestration |
| `payments-mock` | http://127.0.0.1:8083 | Mock payments + fault injection |

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
chmod +x scripts/bootstrap-kind.sh scripts/smoke-test.sh
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh
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

## Tear down

```bash
kind delete cluster --name reliable-app
```

## Layout

```text
app/           FastAPI services (catalog, checkout, payments-mock)
infra/k8s/     Kind config + Kustomize manifests
scripts/       bootstrap-kind.sh, smoke-test.sh
automation/    self-heal / circuit breaker (later)
runbooks/      incident guides (later)
```

---

Built by **[Con Alma Tech](https://conalma.tech)** — SRE packages with soul.
