"""Pydantic schemas for payments-mock."""

from pydantic import BaseModel, Field


class HealthOut(BaseModel):
    status: str


class ChargeIn(BaseModel):
    checkout_id: str
    amount_cents: int = Field(gt=0)
    currency: str = "USD"


class ChargeOut(BaseModel):
    charge_id: str
    checkout_id: str
    status: str
    amount_cents: int
    currency: str


class FaultConfigIn(BaseModel):
    """API-driven fault injection for SRE demos (no redeploy)."""

    latency_ms: int = Field(default=0, ge=0, description="Artificial delay before responding")
    error_rate: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Probability of returning HTTP 500 on /charge",
    )
    timeout: bool = Field(
        default=False,
        description="If true, hang until client times out (demo saturation)",
    )


class FaultConfigOut(FaultConfigIn):
    pass
