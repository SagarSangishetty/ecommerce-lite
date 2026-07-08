# database.py
# Handles database connection and table creation
# Connection string comes from environment variable — never hardcoded

import os
import logging
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

logger = logging.getLogger(__name__)

# Read from environment variable
# In local dev: set in .env file
# In Kubernetes: injected via secret
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:password@localhost:5432/ecommerce")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# User table definition
class UserModel(Base):
    __tablename__ = "users"

    id       = Column(Integer, primary_key=True, index=True)
    name     = Column(String(100), nullable=False)
    email    = Column(String(100), unique=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


def create_tables():
    """Create tables on startup if they don't exist"""
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error(f"Failed to create tables: {e}")
        raise


def get_db():
    """
    Dependency injection for database session.
    Yields a session and ensures it's closed after use.
    Used in routes via FastAPI's Depends()
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()