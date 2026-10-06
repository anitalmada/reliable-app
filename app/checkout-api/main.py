"""checkout-api — create checkout, pay via payments-mock (Reliable App).

Endpoints:
  GET  /health
  GET  /circuit
  POST /checkout
  GET  /checkout/{id}
  POST /checkout/{id}/pay
  GET  /metrics
"""

import json
import os
import uuid
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, HTTPException, status
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy.orm import Session

from circuit_breaker import CircuitBreaker
from db import Base, engine, get_db
from models import Checkout
from schemas import (
    CheckoutCreateIn,
    CheckoutItemOut,
    CheckoutOut,
    CircuitOut,
    HealthOut,
)

PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments-mock:8000")
PAYMENTS_TIMEOUT_S = float(os.getenv("PAYMENTS_TIMEOUT_S", "5"))
CB_FAILURE_THRESHOLD = int(os.getenv("CB_FAILURE_THRESHOLD", "3"))
CB_RECOVERY_TIMEOUT_S = float(os.getenv("CB_RECOVERY_TIMEOUT_S", "30"))

payments_cb = CircuitBreaker(
    failure_threshold=CB_FAILURE_THRESHOLD,
    recovery_timeout_s=CB_RECOVERY_TIMEOUT_S,
)

checkout_total = Counter(
    "checkout_total",
    "Checkouts created / pay outcomes",
    ["status"],
)
payment_failures_total = Counter(
    "payment_failures_total",
    "Checkout payment attempts that failed",
)
circuit_open_total = Counter(
    "payments_circuit_open_total",
    "Pay attempts short-circuited because the payments circuit was open",
)


def checkout_to_out(row: Checkout) -> CheckoutOut:
    items = [CheckoutItemOut(**item) for item in json.loads(row.items_json)]
    return CheckoutOut(
        id=row.id,
        status=row.status,
        items=items,
        total_cents=row.total_cents,
        currency=row.currency,
        charge_id=row.charge_id,
        error_detail=row.error_detail,
        created_at=row.created_at,
    )


@asynccontextmanager
async def lifespan(_app: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="checkout-api",
    description="Checkout orchestration with payments circuit breaker for Reliable App demos.",
    version="0.2.0",
    lifespan=lifespan,
)

Instrumentator(
    should_group_status_codes=False,
    should_ignore_untemplated=True,
    excluded_handlers=["/metrics", "/health"],
).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.get("/health", response_model=HealthOut, tags=["ops"])
def health() -> HealthOut:
    return HealthOut(status="ok")


@app.get("/circuit", response_model=CircuitOut, tags=["ops"])
def circuit_status() -> CircuitOut:
    snap = payments_cb.snapshot()
    return CircuitOut(**snap)


@app.post(
    "/checkout",
    response_model=CheckoutOut,
    status_code=status.HTTP_201_CREATED,
    tags=["checkout"],
)
def create_checkout(body: CheckoutCreateIn, db: Session = Depends(get_db)) -> CheckoutOut:
    expected = sum(i.quantity * i.unit_price_cents for i in body.items)
    if expected != body.total_cents:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"total_cents {body.total_cents} does not match items sum {expected}",
        )

    row = Checkout(
        id=str(uuid.uuid4()),
        status="pending",
        items_json=json.dumps([i.model_dump() for i in body.items]),
        total_cents=body.total_cents,
        currency=body.currency,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    checkout_total.labels(status="pending").inc()
    return checkout_to_out(row)


@app.get("/checkout/{checkout_id}", response_model=CheckoutOut, tags=["checkout"])
def get_checkout(checkout_id: str, db: Session = Depends(get_db)) -> CheckoutOut:
    row = db.get(Checkout, checkout_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Checkout {checkout_id} not found",
        )
    return checkout_to_out(row)


@app.post("/checkout/{checkout_id}/pay", response_model=CheckoutOut, tags=["checkout"])
def pay_checkout(checkout_id: str, db: Session = Depends(get_db)) -> CheckoutOut:
    row = db.get(Checkout, checkout_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Checkout {checkout_id} not found",
        )
    if row.status == "completed":
        return checkout_to_out(row)

    # Circuit open → degrade without calling payments (app stays up).
    if not payments_cb.allow_request():
        circuit_open_total.inc()
        row.status = "degraded"
        row.error_detail = (
            "Payment under maintenance — retrying in background "
            f"(circuit={payments_cb.state.value})"
        )
        db.commit()
        db.refresh(row)
        checkout_total.labels(status="degraded").inc()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=row.error_detail,
        )

    try:
        with httpx.Client(timeout=PAYMENTS_TIMEOUT_S) as client:
            response = client.post(
                f"{PAYMENTS_URL.rstrip('/')}/charge",
                json={
                    "checkout_id": row.id,
                    "amount_cents": row.total_cents,
                    "currency": row.currency,
                },
            )
    except httpx.RequestError as exc:
        payments_cb.record_failure()
        payment_failures_total.inc()
        row.status = "failed"
        row.error_detail = f"payments-mock unreachable: {exc}"
        db.commit()
        db.refresh(row)
        checkout_total.labels(status="failed").inc()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=row.error_detail,
        ) from exc

    if response.status_code >= 500:
        payments_cb.record_failure()
        payment_failures_total.inc()
        row.status = "failed"
        row.error_detail = response.text
        db.commit()
        db.refresh(row)
        checkout_total.labels(status="failed").inc()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Payment processor returned an error",
        )

    if response.status_code >= 400:
        payments_cb.record_failure()
        payment_failures_total.inc()
        row.status = "failed"
        row.error_detail = response.text
        db.commit()
        db.refresh(row)
        checkout_total.labels(status="failed").inc()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Payment rejected",
        )

    payments_cb.record_success()
    payload = response.json()
    row.status = "completed"
    row.charge_id = payload.get("charge_id")
    row.error_detail = None
    db.commit()
    db.refresh(row)
    checkout_total.labels(status="completed").inc()
    return checkout_to_out(row)
