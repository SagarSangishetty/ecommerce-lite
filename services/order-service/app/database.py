# database.py
# Orders table
# Stores order with user_id, product_id, quantity and status
# Status values: pending, confirmed, failed

import os
import logging
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://user:password@localhost:5432/ecommerce"
)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class OrderModel(Base):
    __tablename__ = "orders"

    id          = Column(Integer, primary_key=True, index=True)
    user_id     = Column(Integer, nullable=False)
    product_id  = Column(Integer, nullable=False)
    quantity    = Column(Integer, nullable=False)
    total_price = Column(Float, nullable=False)
    status      = Column(String(50), default="confirmed")
    created_at  = Column(DateTime, default=datetime.utcnow)


def create_tables():
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Order service DB tables created successfully")
    except Exception as e:
        logger.error(f"Failed to create tables: {e}")
        raise


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()