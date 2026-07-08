// app.js
// Entry point for frontend service
//
// Responsibilities:
// - Serve HTML pages to browser
// - Generate X-Request-ID for every incoming request
// - Pass X-Request-ID to all backend service calls
// - Expose /metrics for Prometheus
// - Structured JSON logging via Winston

const express  = require('express');
const axios    = require('axios');
const { v4: uuidv4 } = require('uuid');
const winston  = require('winston');
const client   = require('prom-client');
const path     = require('path');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));


// ── SERVICE URLS ────────────────────────────────────────────────
// In Kubernetes these resolve to internal service DNS
// e.g. http://user-service:8001
// In local dev point to localhost ports

const USER_SERVICE_URL    = process.env.USER_SERVICE_URL    || 'http://localhost:8001';
const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL || 'http://localhost:8002';
const ORDER_SERVICE_URL   = process.env.ORDER_SERVICE_URL   || 'http://localhost:8003';


// ── STRUCTURED JSON LOGGING ─────────────────────────────────────
// Winston logger — outputs JSON
// Fluent Bit collects these logs from the pod
// and ships to Elasticsearch

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'frontend' },
  transports: [new winston.transports.Console()]
});


// ── PROMETHEUS METRICS ──────────────────────────────────────────

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestCount = new client.Counter({
  name: 'frontend_requests_total',
  help: 'Total requests to frontend',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestDuration = new client.Histogram({
  name: 'frontend_request_duration_seconds',
  help: 'Frontend request duration',
  labelNames: ['method', 'route'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
  registers: [register]
});


// ── MIDDLEWARE ──────────────────────────────────────────────────
// Runs on every request
// Generates X-Request-ID if not present
// Attaches to req object so all route handlers can use it
// Logs request start and completion with duration

app.use((req, res, next) => {
  const startTime = Date.now();

  // Generate or read X-Request-ID
  req.requestId = req.headers['x-request-id'] || uuidv4();
  res.setHeader('X-Request-ID', req.requestId);

  logger.info({
    event:      'request_received',
    request_id: req.requestId,
    method:     req.method,
    path:       req.path
  });

  res.on('finish', () => {
    const duration = (Date.now() - startTime) / 1000;

    httpRequestCount.labels(req.method, req.path, res.statusCode).inc();
    httpRequestDuration.labels(req.method, req.path).observe(duration);

    logger.info({
      event:       'request_completed',
      request_id:  req.requestId,
      method:      req.method,
      path:        req.path,
      status_code: res.statusCode,
      duration_ms: Date.now() - startTime
    });
  });

  next();
});


// ── HELPER — AXIOS WITH REQUEST ID ─────────────────────────────
// Every call to backend services includes X-Request-ID header
// This is what connects frontend trace to backend traces in Jaeger

function backendCall(requestId) {
  return axios.create({
    headers: { 'X-Request-ID': requestId },
    timeout: 5000
  });
}


// ── ROUTES ─────────────────────────────────────────────────────

// HOME — list all products
app.get('/', async (req, res) => {
  try {
    const response = await backendCall(req.requestId)
      .get(`${PRODUCT_SERVICE_URL}/products`);

    logger.info({
      event:      'fetch_products_success',
      request_id: req.requestId,
      count:      response.data.length
    });

    res.render('index', {
      products:   response.data,
      request_id: req.requestId
    });

  } catch (err) {
    logger.error({
      event:      'fetch_products_failed',
      request_id: req.requestId,
      error:      err.message
    });
    res.render('error', {
      message:    'Failed to load products',
      request_id: req.requestId
    });
  }
});


// REGISTER PAGE — show registration form
app.get('/register', (req, res) => {
  res.render('register', {
    request_id: req.requestId,
    message:    null
  });
});


// REGISTER — submit new user
app.post('/register', async (req, res) => {
  const { name, email } = req.body;

  try {
    await backendCall(req.requestId)
      .post(`${USER_SERVICE_URL}/users`, { name, email });

    logger.info({
      event:      'user_registered',
      request_id: req.requestId,
      email:      email
    });

    res.render('register', {
      request_id: req.requestId,
      message:    `User ${name} registered successfully!`
    });

  } catch (err) {
    const detail = err.response?.data?.detail || err.message;

    logger.error({
      event:      'user_registration_failed',
      request_id: req.requestId,
      error:      detail
    });

    res.render('register', {
      request_id: req.requestId,
      message:    `Error: ${detail}`
    });
  }
});


// ORDER PAGE — show order form
app.get('/order', async (req, res) => {
  try {
    const response = await backendCall(req.requestId)
      .get(`${PRODUCT_SERVICE_URL}/products`);

    res.render('order', {
      products:   response.data,
      request_id: req.requestId,
      message:    null
    });

  } catch (err) {
    logger.error({
      event:      'fetch_products_for_order_failed',
      request_id: req.requestId,
      error:      err.message
    });
    res.render('error', {
      message:    'Failed to load products for order',
      request_id: req.requestId
    });
  }
});


// ORDER — place an order
app.post('/order', async (req, res) => {
  const { user_id, product_id, quantity } = req.body;

  try {
    const response = await backendCall(req.requestId)
      .post(`${ORDER_SERVICE_URL}/orders`, {
        user_id:    parseInt(user_id),
        product_id: parseInt(product_id),
        quantity:   parseInt(quantity)
      });

    logger.info({
      event:      'order_placed_success',
      request_id: req.requestId,
      order_id:   response.data.id,
      total:      response.data.total_price