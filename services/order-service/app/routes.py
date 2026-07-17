# routes.py
# Order service endpoints
#
# KEY CONCEPT — inter-service communication:
# When placing an order, order-service calls:
#   1. user-service    → validate user exists
#   2. product-service → validate product exists + check stock
#   3. product-service → update stock after order confirmed
#
# The X-Request-ID is passed in every inter-service call
# This means Jaeger shows one trace spanning all 3 services
# for a single place-order request

import logging
import uuid
import os
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List
from .database import get_db, OrderModel

logger = logging.getLogger(__name__)

router = APIRouter()

# Service URLs — injected via environment variables
# In Kubernetes these point to internal service DNS names
# e.g. http://user-service:8001
# In local dev these point to localhost ports
USER_SERVICE_URL    = os.getenv("USER_SERVICE_URL",    "http://localhost:8001")
PRODUCT_SERVICE_URL = os.getenv("PRODUCT_SERVICE_URL", "http://localhost:8002")


# ── SCHEMAS ────────────────────────────────────────────────────

class OrderCreate(BaseModel):
    user_id:    int
    product_id: int
    quantity:   int


class OrderResponse(BaseModel):
    id:          int
    user_id:     int
    product_id:  int
    quantity:    int
    total_price: float
    status:      str

    class Config:
        from_attributes = True


# ── HELPER ─────────────────────────────────────────────────────

def get_request_id(request: Request) -> str:
    return request.headers.get("X-Request-ID", str(uuid.uuid4()))


def build_headers(request_id: str) -> dict:
    """
    Build headers for inter-service calls.
    Always includes X-Request-ID so the same trace ID
    flows through user-service and product-service.
    This is what connects spans across services in Jaeger.
    """
    return {
        "X-Request-ID": request_id,
        "Content-Type": "application/json"
    }


# ── ENDPOINTS ──────────────────────────────────────────────────

@router.get("/health")
def health_check():
    return {"status": "healthy", "service": "order-service"}


@router.post("/orders", response_model=OrderResponse, status_code=201)
async def create_order(
    order_data: OrderCreate,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Place a new order.

    Flow:
    1. Validate user exists (calls user-service)
    2. Validate product exists and has enough stock
       (calls product-service)
    3. Calculate total price
    4. Save order to database
    5. Deduct stock (calls product-service)
    6. Return confirmed order

    If any step fails → order is not placed.
    All failures are logged with request_id for tracing.

    THIS IS THE ALERT SCENARIO:
    If product-service or user-service is down,
    this endpoint starts returning 500 errors.
    Prometheus records these, Grafana alert fires
    when error rate crosses threshold.
    """
    request_id = get_request_id(request)
    headers    = build_headers(request_id)

    logger.info({
        "event":      "create_order_request",
        "request_id": request_id,
        "user_id":    order_data.user_id,
        "product_id": order_data.product_id,
        "quantity":   order_data.quantity
    })

    # ── STEP 1: Validate user exists ───────────────────────────
    try:
        async with httpx.AsyncClient() as client:
            user_response = await client.get(
                f"{USER_SERVICE_URL}/users/{order_data.user_id}",
                headers=headers,
                timeout=5.0
            )

        if user_response.status_code == 404:
            logger.warning({
                "event":      "create_order_user_not_found",
                "request_id": request_id,
                "user_id":    order_data.user_id
            })
            raise HTTPException(
                status_code=404,
                detail=f"User {order_data.user_id} not found"
            )

        if user_response.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail="User service unavailable"
            )

    except httpx.TimeoutException:
        logger.error({
            "event":      "create_order_user_service_timeout",
            "request_id": request_id
        })
        raise HTTPException(
            status_code=504,
            detail="User service timed out"
        )

    except httpx.ConnectError:
        logger.error({
            "event":      "create_order_user_service_unreachable",
            "request_id": request_id
        })
        raise HTTPException(
            status_code=503,
            detail="User service unreachable"
        )

    # ── STEP 2: Validate product and check stock ───────────────
    try:
        async with httpx.AsyncClient() as client:
            product_response = await client.get(
                f"{PRODUCT_SERVICE_URL}/products/{order_data.product_id}",
                headers=headers,
                timeout=5.0
            )

        if product_response.status_code == 404:
            logger.warning({
                "event":      "create_order_product_not_found",
                "request_id": request_id,
                "product_id": order_data.product_id
            })
            raise HTTPException(
                status_code=404,
                detail=f"Product {order_data.product_id} not found"
            )

        product = product_response.json()

        # Check stock availability
        if product["stock"] < order_data.quantity:
            logger.warning({
                "event":           "create_order_insufficient_stock",
                "request_id":      request_id,
                "product_id":      order_data.product_id,
                "requested":       order_data.quantity,
                "available_stock": product["stock"]
            })
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient stock. Available: {product['stock']}"
            )

    except httpx.TimeoutException:
        logger.error({
            "event":      "create_order_product_service_timeout",
            "request_id": request_id
        })
        raise HTTPException(
            status_code=504,
            detail="Product service timed out"
        )

    except httpx.ConnectError:
        logger.error({
            "event":      "create_order_product_service_unreachable",
            "request_id": request_id
        })
        raise HTTPException(
            status_code=503,
            detail="Product service unreachable"
        )

    # ── STEP 3: Calculate total and save order ─────────────────
    total_price = product["price"] * order_data.quantity

    new_order = OrderModel(
        user_id=order_data.user_id,
        product_id=order_data.product_id,
        quantity=order_data.quantity,
        total_price=total_price,
        status="confirmed"
    )
    db.add(new_order)
    db.commit()
    db.refresh(new_order)

    logger.info({
        "event":      "create_order_saved",
        "request_id": request_id,
        "order_id":   new_order.id,
        "total":      total_price
    })

    # ── STEP 4: Deduct stock ───────────────────────────────────
    try:
        async with httpx.AsyncClient() as client:
            await client.patch(
                f"{PRODUCT_SERVICE_URL}/products/{order_data.product_id}/stock",
                json={"quantity": -order_data.quantity},
                headers=headers,
                timeout=5.0
            )
    except Exception as e:
        # Order is already saved — log the stock update failure
        # but don't fail the order. Flag for manual review.
        logger.error({
            "event":      "create_order_stock_update_failed",
            "request_id": request_id,
            "order_id":   new_order.id,
            "error":      str(e)
        })

    logger.info({
        "event":      "create_order_success",
        "request_id": request_id,
        "order_id":   new_order.id,
        "user_id":    order_data.user_id,
        "product_id": order_data.product_id,
        "total":      total_price
    })

    return new_order


@router.get("/orders/{order_id}", response_model=OrderResponse)
def get_order(
    order_id: int,
    request: Request,
    db: Session = Depends(get_db)
):
    """Get a single order by ID"""
    request_id = get_request_id(request)

    logger.info({
        "event":      "get_order_request",
        "request_id": request_id,
        "order_id":   order_id
    })

    order = db.query(OrderModel).filter(
        OrderModel.id == order_id
    ).first()

    if not order:
        logger.warning({
            "event":      "get_order_not_found",
            "request_id": request_id,
            "order_id":   order_id
        })
        raise HTTPException(
            status_code=404,
            detail="Order not found"
        )

    return order


@router.get("/orders/user/{user_id}", response_model=List[OrderResponse])
def get_orders_by_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db)
):
    """Get all orders for a specific user"""
    request_id = get_request_id(request)

    logger.info({
        "event":      "get_user_orders_request",
        "request_id": request_id,
        "user_id":    user_id
    })

    orders = db.query(OrderModel).filter(
        OrderModel.user_id == user_id
    ).all()

    logger.info({
        "event":      "get_user_orders_success",
        "request_id": request_id,
        "user_id":    user_id,
        "count":      len(orders)
    })

    return orders