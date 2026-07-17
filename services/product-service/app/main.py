# main.py
# Entry point for product service
# Identical observability setup to user-service
# — same pattern across all services deliberately
# This consistency makes debugging easier in production

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


# ── STRUCTURED JSON LOGGING ─────────────────────────────────────

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record),
            "level":     record.levelname,
            "service":   "product-service",
            "message":   record.getMessage()
        }
        if isinstance(record.msg, dict):
            log_entry.update(record.msg)
            log_entry["message"] = record.levelname
        return json.dumps(log_entry)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger(__name__)


# ── OPENTELEMETRY ───────────────────────────────────────────────

OTEL_ENDPOINT = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "http://otel-collector:4317"
)

resource  = Resource.create({"service.name": "product-service"})
provider  = TracerProvider(resource=resource)
exporter  = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)


# ── PROMETHEUS METRICS ──────────────────────────────────────────

REQUEST_COUNT = Counter(
    "product_service_requests_total",
    "Total requests to product service",
    ["method", "endpoint", "status_code"]
)

REQUEST_LATENCY = Histogram(
    "product_service_request_duration_seconds",
    "Request latency for product service",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)


# ── FASTAPI APP ─────────────────────────────────────────────────

app = FastAPI(
    title="Product Service",
    description="Manages product catalogue and stock",
    version="1.0.0"
)

FastAPIInstrumentor.instrument_app(app)
app.include_router(router)


# ── MIDDLEWARE ──────────────────────────────────────────────────

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
        "event":       "request_completed",
        "request_id":  request_id,
        "method":      request.method,
        "path":        request.url.path,
        "status_code": response.status_code,
        "duration_ms": round(duration * 1000, 2)
    })

    response.headers["X-Request-ID"] = request_id
    return response


# ── METRICS ENDPOINT ────────────────────────────────────────────

@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


# ── STARTUP ─────────────────────────────────────────────────────

@app.on_event("startup")
def on_startup():
    logger.info({
        "event":   "service_startup",
        "service": "product-service",
        "message": "Starting product service and creating DB tables"
    })
    create_tables()