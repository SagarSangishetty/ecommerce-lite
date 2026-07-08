# ── STAGE 1: Builder ────────────────────────────────────────────
# Install dependencies in a separate stage
# So the final image doesn't carry pip cache or build tools

FROM python:3.11-slim AS builder

WORKDIR /app

# Copy requirements first — Docker layer caching
# If requirements.txt doesn't change, this layer is cached
# Only re-runs when requirements.txt changes
COPY requirements.txt .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir --user -r requirements.txt


# ── STAGE 2: Final image ────────────────────────────────────────
# Clean base image — only copy what's needed
# Results in smaller, more secure image

FROM python:3.11-slim

WORKDIR /app

# Create non-root user
# Never run containers as root in production
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy installed packages from builder stage
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY app/ ./app/

# Set PATH so Python finds packages installed by builder
ENV PATH=/home/appuser/.local/bin:$PATH

# Switch to non-root user
USER appuser

# Expose service port
EXPOSE 8001

# Health check — Docker will mark container unhealthy
# if this fails — Kubernetes also uses this
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"

# Start the service
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001"]