"""payments-mock — simulate a payment processor (Reliable App Phase 0).

Endpoints (Scope — Minimal App):
  GET  /health
  POST /charge
  POST /admin/faults   — latency, 5xx %, hang/timeout
  GET  /admin/faults
  GET  /metrics
"""

import asyncio
import random
import uuid
from dataclasses import dataclass

from fastapi import FastAPI, HTTPException, status
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator

from schemas import (
    ChargeIn,
    ChargeOut,
    FaultConfigIn,
    FaultConfigOut,
    HealthOut,
)

payment_failures_total = Counter(
    "payment_failures_total",
    "Payment charges that failed (injected 5xx or rejected)",
)


@dataclass
class FaultState:
    latency_ms: int = 0
    error_rate: float = 0.0
    timeout: bool = False


faults = FaultState()

app = FastAPI(
    title="payments-mock",
    description="Mock payment processor with injectable faults for Reliable App demos.",
    version="0.1.0",
)

Instrumentator(
    should_group_status_codes=False,
    should_ignore_untemplated=True,
    excluded_handlers=["/metrics", "/health"],
).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.get("/health", response_model=HealthOut, tags=["ops"])
def health() -> HealthOut:
    return HealthOut(status="ok")


@app.get("/admin/faults", response_model=FaultConfigOut, tags=["chaos"])
def get_faults() -> FaultConfigOut:
    return FaultConfigOut(
        latency_ms=faults.latency_ms,
        error_rate=faults.error_rate,
        timeout=faults.timeout,
    )


@app.post("/admin/faults", response_model=FaultConfigOut, tags=["chaos"])
def set_faults(body: FaultConfigIn) -> FaultConfigOut:
    faults.latency_ms = body.latency_ms
    faults.error_rate = body.error_rate
    faults.timeout = body.timeout
    return get_faults()


@app.post("/charge", response_model=ChargeOut, tags=["payments"])
async def charge(body: ChargeIn) -> ChargeOut:
    if faults.timeout:
        # Hang until the caller (checkout-api) times out — demos saturation.
        await asyncio.sleep(3600)

    if faults.latency_ms > 0:
        await asyncio.sleep(faults.latency_ms / 1000.0)

    if faults.error_rate > 0 and random.random() < faults.error_rate:
        payment_failures_total.inc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Injected payment processor failure",
        )

    return ChargeOut(
        charge_id=str(uuid.uuid4()),
        checkout_id=body.checkout_id,
        status="succeeded",
        amount_cents=body.amount_cents,
        currency=body.currency,
    )
