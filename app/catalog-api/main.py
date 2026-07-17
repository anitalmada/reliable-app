"""catalog-api — list and get products (Reliable App Phase 0).

Endpoints (Scope — Minimal App):
  GET /health
  GET /products
  GET /products/{id}
  GET /metrics   (Prometheus; via instrumentator)
"""

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, status
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy.orm import Session

from db import Base, engine, get_db
from models import Product
from schemas import HealthOut, ProductOut

SEED_PRODUCTS = [
    {
        "id": 1,
        "name": "Reliable Mug",
        "description": "Ceramic mug for long on-call nights.",
        "price_cents": 1500,
        "currency": "USD",
    },
    {
        "id": 2,
        "name": "SLO Sticker Pack",
        "description": "Four golden signals, one laptop lid.",
        "price_cents": 500,
        "currency": "USD",
    },
    {
        "id": 3,
        "name": "Error Budget Notebook",
        "description": "Track burn rate the analog way.",
        "price_cents": 2200,
        "currency": "USD",
    },
]


def seed_products() -> None:
    """Insert demo products if the table is empty."""
    with Session(engine) as db:
        if db.query(Product).count() > 0:
            return
        for item in SEED_PRODUCTS:
            db.add(Product(**item))
        db.commit()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    Base.metadata.create_all(bind=engine)
    seed_products()
    yield


app = FastAPI(
    title="catalog-api",
    description="Minimal product catalog for Reliable App demos.",
    version="0.1.0",
    lifespan=lifespan,
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")


@app.get("/health", response_model=HealthOut, tags=["ops"])
def health() -> HealthOut:
    return HealthOut(status="ok")


@app.get("/products", response_model=list[ProductOut], tags=["catalog"])
def list_products(db: Session = Depends(get_db)) -> list[Product]:
    return db.query(Product).order_by(Product.id).all()


@app.get("/products/{product_id}", response_model=ProductOut, tags=["catalog"])
def get_product(product_id: int, db: Session = Depends(get_db)) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product {product_id} not found",
        )
    return product
