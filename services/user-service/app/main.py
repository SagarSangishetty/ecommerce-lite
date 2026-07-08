# main.py
# Entry point for user service
# Sets up:
#   - Structured JSON logging
#   - OpenTelemetry tracing
#   - Prometheus metrics
#   - FastAPI app with all routes

import logging
import json
import os
import time
from fastapi import FastAPI, Request, Response
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from .database import create_tables
from .routes import router


# ── STRUCTURED JSON LOGGING SETUP ──────────────────────────────
# Every log line is JSON — makes Fluent Bit parsing easy
# and allows Kibana to index individual fields

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record),
            "level":     record.levelname,
            "service":   "user-service",
            "message":   record.getMessage()
        }
        # If message is already a dict (from our routes), merge it
        if isinstance(record.msg, dict):
            log_entry.update(record.msg)
            log_entry["message"] = record.levelname
        return json.dumps(log_entry)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger(__name__)


# ── OPENTELEMETRY SETUP ─────────────────────────────────────────
# Sends traces to OTel Collector
# OTEL_EXPORTER_OTLP_ENDPOINT comes from environment variable
# In Kubernetes this points to the OTel Collector service

OTEL_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://otel-collector:4317"
)

resource = Resource.create({"service.name": "user-service"})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)


# ── PROMETHEUS METRICS ──────────────────────────────────────────
# Two metrics per service — request count and latency
# Labels: method (GET/POST), endpoint, status code

REQUEST_COUNT = Counter(
    "user_service_requests_total",
    "Total number of requests to user service",
    ["method", "endpoint", "status_code"]
)

REQUEST_LATENCY = Histogram(
    "user_service_request_duration_seconds",
    "Request latency for user service",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)


# ── FASTAPI APP ─────────────────────────────────────────────────

app = FastAPI(
    title="User Service",
    description="Handles user registration and retrieval",
    version="1.0.0"
)

# Auto-instrument FastAPI with OpenTelemetry
# This creates spans for every request automatically
FastAPIInstrumentor.instrument_app(app)

# Register routes
app.include_router(router)


# ── MIDDLEWARE — REQUEST TRACKING ───────────────────────────────
# Runs on every request
# Records metrics and logs with X-Request-ID

@app.middleware("http")
async def track_requests(request: Request, call_next):
    start_time = time.time()
    request_id = request.headers.get("X-Request-ID", "no-request-id")

    logger.info({
        "event":      "request_received",
        "request_id": request_id,
        "method":     request.method,
        "path":       request.url.path
    })

    response = await call_next(request)

    duration = time.time() - start_time

    # Record Prometheus metrics
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status_code=response.status_code
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    logger.info({
        "event":        "request_completed",
        "request_id":   request_id,
        "method":       request.method,
        "path":         request.url.path,
        "status_code":  response.status_code,
        "duration_ms":  round(duration * 1000, 2)
    })

    # Pass X-Request-ID in response headers too
    response.headers["X-Request-ID"] = request_id
    return response


# ── PROMETHEUS METRICS ENDPOINT ─────────────────────────────────
# Prometheus scrapes this endpoint every 15 seconds
# Must return plain text in Prometheus exposition format

@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


# ── STARTUP EVENT ───────────────────────────────────────────────

@app.on_event("startup")
def on_startup():
    logger.info({
        "event":   "service_startup",
        "service": "user-service",
        "message": "Starting user service and creating DB tables"
    })
    create_tables()