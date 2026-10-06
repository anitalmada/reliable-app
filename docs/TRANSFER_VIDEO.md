# Transfer video — outline (5–10 min)

Record with **Loom** or unlisted **YouTube**. Mention **Con Alma Tech** and https://conalma.tech in the intro and outro.

**Status:** script ready — video link TBD (paste URL into README EN/ES when published).

## Goal

An outsider can watch once and then run an incident with only the runbooks.

## Suggested chapter timestamps

| Time | Chapter | On screen |
|---|---|---|
| 0:00 | Who we are | Con Alma Tech · conalma.tech · Reliable App portfolio |
| 0:30 | Stack tour | Kind · three APIs · Grafana · Prometheus · Alertmanager |
| 1:30 | Healthy baseline | Executive dashboard green · `./scripts/query-error-budget.sh` |
| 2:30 | Break payments | Inject latency via `/admin/faults` or start `demo-latency-alert.sh` |
| 4:00 | Alert fires | PAGE `ErrorBudgetBurnFastPaymentLatency` · inbox `/pager` |
| 5:00 | Self-heal | `GET /actions` · faults cleared · `payments-mock` restart |
| 6:00 | Circuit breaker | `./scripts/demo-circuit-breaker.sh` · 503 degraded · `/circuit` |
| 7:30 | Runbook walkthrough | Open `runbooks/RB_ERR_BUDGET_BURN_FAST.md` · show diagnose + manual mitigate |
| 9:00 | Close | Point to GitLab (ES) / GitHub (EN) · invite transfer session |

## Talking points (do not read verbatim)

1. **We alert on error-budget burn, not CPU &gt; 80%.**
2. **Self-heal writes evidence first, then mitigates** — pattern over magic.
3. **Circuit breaker keeps checkout up** while payments are sick.
4. **Runbooks answer: impact → diagnose → mitigate if automation fails.**

## Demo commands (keep a second terminal ready)

```bash
./scripts/bootstrap-kind.sh   # if cold start
./scripts/query-error-budget.sh
# either full alert path (~3–4 min):
./scripts/demo-latency-alert.sh
# or fast heal path:
./scripts/demo-self-heal.sh
./scripts/demo-circuit-breaker.sh
```

## After recording

1. Publish unlisted / Loom link.
2. Replace `VIDEO_URL_PLACEHOLDER` in `README.md` and `README.es.md`.
3. Paste the same URL into Obsidian Phase 5 Evidence.
