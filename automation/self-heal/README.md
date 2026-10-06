# Self-heal webhook

```text
Alertmanager (P1 page)
        │
        ▼
 POST /webhook  (self-heal)
        │
        ├─► write evidence stub (/evidence)
        ├─► reset payments-mock faults
        └─► rollout restart Deployment/payments-mock
```

## Endpoints

| Path | Purpose |
|---|---|
| `POST /webhook` | Alertmanager webhook |
| `GET /actions` | Recent heal actions |
| `GET /evidence` | Evidence files collected |
| `GET /health` | Liveness |

## RBAC

In-cluster ServiceAccount can `patch` Deployments in `reliable-app` (rollout restart via annotation).

## Demo

```bash
./scripts/demo-self-heal.sh
curl -s http://127.0.0.1:8085/actions | python3 -m json.tool
```
