# Ecommerce Lite — Production Grade on AWS EKS

A 3-tier microservices application built with production-grade 
DevOps practices.

## Architecture
- **Frontend**: Node.js + Express
- **Backend**: 3 Python FastAPI microservices
  - User Service (port 8001)
  - Product Service (port 8002)
  - Order Service (port 8003)
- **Database**: PostgreSQL

## Infrastructure
- AWS EKS (Kubernetes)
- Terraform (VPC + EKS provisioning)
- GitHub Actions CI/CD (OIDC — no static keys)
- AWS ECR (private image registry)

## Observability
- Metrics: Prometheus + Grafana
- Logging: Fluent Bit + Elasticsearch + Kibana (EFK)
- Tracing: OpenTelemetry + Jaeger
- Correlation: X-Request-ID across all services

## Environments
- `dev` namespace — triggered on merge to dev branch
- `prod` namespace — triggered on merge to main branch

## Branching Strategy
- `main` → production
- `dev` → development
- `feature/*` → active work, merged to dev via PR
