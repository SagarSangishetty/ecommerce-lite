# routes.py
# All API endpoints for user service
# X-Request-ID flows through every endpoint and every log line

import logging
import uuid
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from .database import get_db, UserModel

logger = logging.getLogger(__name__)

router = APIRouter()


# ── REQUEST / RESPONSE SCHEMAS ─────────────────────────────────

class UserCreate(BaseModel):
    name:  str
    email: str


class UserResponse(BaseModel):
    id:    int
    name:  str
    email: str

    class Config:
        from_attributes = True


# ── HELPER ─────────────────────────────────────────────────────

def get_request_id(request: Request) -> str:
    """
    Read X-Request-ID from incoming header.
    If not present, generate a new one.
    This ensures every request has a trace ID
    whether it comes from frontend or direct API call.
    """
    return request.headers.get("X-Request-ID", str(uuid.uuid4()))


# ── ENDPOINTS ──────────────────────────────────────────────────

@router.get("/health")
def health_check():
    """
    Health check endpoint.
    Kubernetes liveness and readiness probes call this.
    Returns 200 if service is running.
    """
    return {"status": "healthy", "service": "user-service"}


@router.post("/users", response_model=UserResponse, status_code=201)
def create_user(
    user_data: UserCreate,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Create a new user.
    Checks for duplicate email before inserting.
    Logs every step with X-Request-ID for tracing.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "create_user_request",
        "request_id": request_id,
        "email":      user_data.email
    })

    # Check if email already exists
    existing = db.query(UserModel).filter(
        UserModel.email == user_data.email
    ).first()

    if existing:
        logger.warning({
            "event":      "create_user_duplicate_email",
            "request_id": request_id,
            "email":      user_data.email
        })
        raise HTTPException(
            status_code=400,
            detail="Email already registered"
        )

    # Create and save new user
    new_user = UserModel(
        name=user_data.name,
        email=user_data.email
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    logger.info({
        "event":      "create_user_success",
        "request_id": request_id,
        "user_id":    new_user.id
    })

    return new_user


@router.get("/users/{user_id}", response_model=UserResponse)
def get_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Fetch a user by ID.
    Returns 404 if user not found.
    """
    request_id = get_request_id(request)

    logger.info({
        "event":      "get_user_request",
        "request_id": request_id,
        "user_id":    user_id
    })

    user = db.query(UserModel).filter(
        UserModel.id == user_id
    ).first()

    if not user:
        logger.warning({
            "event":      "get_user_not_found",
            "request_id": request_id,
            "user_id":    user_id
        })
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    return user