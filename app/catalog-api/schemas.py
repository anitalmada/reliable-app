"""Pydantic schemas for catalog-api responses."""

from pydantic import BaseModel, ConfigDict


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str
    price_cents: int
    currency: str


class HealthOut(BaseModel):
    status: str
