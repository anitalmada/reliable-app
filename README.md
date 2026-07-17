# Reliable App

Minimal e-commerce demo for **Con Alma Tech** SRE service packages.

Three FastAPI services on local **Kind**, with injectable payment faults and Prometheus `/metrics` on each API.

| Service | Local URL | Role |
|---|---|---|
| `catalog-api` | http://127.0.0.1:8081 | Product list / detail |
| `checkout-api` | http://127.0.0.1:8082 | Checkout + pay orchestration |
| `payments-mock` | http://127.0.0.1:8083 | Mock payments + fault injection |

Site: [conalma.tech](https://conalma.tech)  
Spanish docs / canonical repo: [GitLab](https://gitlab.com/anitalmada/reliable-app) · English: [GitHub](https://github.com/anitalmada/reliable-app)

## Prerequisites

- Docker (daemon running)
- `curl` and `python3` (for smoke test)
- `kind` and `kubectl` — installed automatically by the bootstrap script into `~/.local/bin` if missing

## Bring up (Kind)

```bash
chmod +x scripts/bootstrap-kind.sh scripts/smoke-test.sh
./scripts/bootstrap-kind.sh
./scripts/smoke-test.sh
```

OpenAPI: `/docs` on each port above.

## Happy path (manual)

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
app/           FastAPI services
infra/k8s/     Kind config + Kustomize manifests
scripts/       bootstrap-kind.sh, smoke-test.sh
automation/    (Phase 4)
runbooks/      (Phase 5)
```
