# ── STAGE 1: Builder ────────────────────────────────────────────
# Install node modules in builder stage
# Keeps final image clean — no npm cache

FROM node:20-slim AS builder

WORKDIR /app

# Copy package files first — layer caching
# npm install only re-runs when package.json changes
COPY package.json package-lock.json* ./

RUN npm ci --only=production


# ── STAGE 2: Final image ────────────────────────────────────────

FROM node:20-slim

WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application code
COPY src/ ./src/
COPY package.json ./

# Switch to non-root user
USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

CMD ["node", "src/app.js"]