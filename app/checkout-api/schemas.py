"""Pydantic schemas for checkout-api."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class HealthOut(BaseModel):
    status: str


class CircuitOut(BaseModel):
    state: str
    failures: int
    failure_threshold: int
    recovery_timeout_s: float


class CheckoutItemIn(BaseModel):
    product_id: int
    quantity: int = Field(ge=1)
    unit_price_cents: int = Field(ge=0)


class CheckoutCreateIn(BaseModel):
    items: list[CheckoutItemIn] = Field(min_length=1)
    total_cents: int = Field(gt=0)
    currency: str = "USD"


class CheckoutItemOut(BaseModel):
    product_id: int
    quantity: int
    unit_price_cents: int


class CheckoutOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: str
    items: list[CheckoutItemOut]
    total_cents: int
    currency: str
    charge_id: str | None = None
    error_detail: str | None = None
    created_at: datetime | None = None
