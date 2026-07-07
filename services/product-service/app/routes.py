# routes.py
# Product service endpoints
# Supports: create product, list all, get by ID, update stock
# Stock update is called by order-service when order is placed

import logging
import uuid
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Optional
from .database import get_db, ProductModel

logger = logging.getLogger(__name__)

router = APIRouter()


# ── SCHEMAS ────────────────────────────────────────────────────

class ProductCreate(BaseModel):
    name:        str
    description: Optional[str] = None
    price:       float
    stock:       int


class ProductResponse(BaseModel):
    id:          int
    name:        str
    description: Optional[str]
    price:       float
    stock:       int

    class Config:
        from_attributes = True


class StockUpdate(BaseModel):
    quantity: int  # negative to reduce, positive to add


# ── HELPER ─────────────────────────────────────────────────────

def get_request_id(request: Request) -> str:
    return request.headers.get("X-Request-ID", str(uuid.uuid4()))


# ── ENDPOINTS ──────────────────────────────────────────────────

@router.get("/health")
def health_check():
    return {"status": "healthy", "service": "product-service"}


@router.post("/products", response_model=ProductResponse, status_code=201)
def create_product(
    product_data: ProductCreate,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Create a new product in the catalogue.
    Price must be positive, stock must be non-negative.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "create_product_request",
        "request_id": request_id,
        "name":       product_data.name,
        "price":      product_data.price
    })

    # Validate price
    if product_data.price <= 0:
        logger.warning({
            "event":      "create_product_invalid_price",
            "request_id": request_id,
            "price":      product_data.price
        })
        raise HTTPException(
            status_code=400,
            detail="Price must be greater than 0"
        )

    # Validate stock
    if product_data.stock < 0:
        raise HTTPException(
            status_code=400,
            detail="Stock cannot be negative"
        )

    new_product = ProductModel(
        name=product_data.name,
        description=product_data.description,
        price=product_data.price,
        stock=product_data.stock
    )
    db.add(new_product)
    db.commit()
    db.refresh(new_product)

    logger.info({
        "event":      "create_product_success",
        "request_id": request_id,
        "product_id": new_product.id
    })

    return new_product


@router.get("/products", response_model=List[ProductResponse])
def list_products(
    request: Request,
    db: Session = Depends(get_db)
):
    """
    List all products in the catalogue.
    Frontend calls this to display the product listing page.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "list_products_request",
        "request_id": request_id
    })

    products = db.query(ProductModel).all()

    logger.info({
        "event":      "list_products_success",
        "request_id": request_id,
        "count":      len(products)
    })

    return products


@router.get("/products/{product_id}", response_model=ProductResponse)
def get_product(
    product_id: int,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Get a single product by ID.
    Called by order-service to validate product exists
    before placing an order.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "get_product_request",
        "request_id": request_id,
        "product_id": product_id
    })

    product = db.query(ProductModel).filter(
        ProductModel.id == product_id
    ).first()

    if not product:
        logger.warning({
            "event":      "get_product_not_found",
            "request_id": request_id,
            "product_id": product_id
        })
        raise HTTPException(
            status_code=404,
            detail="Product not found"
        )

    return product


@router.patch("/products/{product_id}/stock")
def update_stock(
    product_id: int,
    stock_data: StockUpdate,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Update product stock.
    Called internally by order-service after order is placed.
    Negative quantity reduces stock (order placed).
    Positive quantity increases stock (restock).
    Prevents stock going below zero.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "update_stock_request",
        "request_id": request_id,
        "product_id": product_id,
        "quantity":   stock_data.quantity
    })

    product = db.query(ProductModel).filter(
        ProductModel.id == product_id
    ).first()

    if not product:
        raise HTTPException(
            status_code=404,
            detail="Product not found"
        )

    new_stock = product.stock + stock_data.quantity

    if new_stock < 0:
        logger.warning({
            "event":        "update_stock_insufficient",
            "request_id":   request_id,
            "product_id":   product_id,
            "current_stock": product.stock,
            "requested":    stock_data.quantity
        })
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient stock. Available: {product.stock}"
        )

    product.stock = new_stock
    db.commit()

    logger.info({
        "event":      "update_stock_success",
        "request_id": request_id,
        "product_id": product_id,
        "new_stock":  new_stock
    })

    return {
        "product_id": product_id,
        "new_stock":  new_stock
    }