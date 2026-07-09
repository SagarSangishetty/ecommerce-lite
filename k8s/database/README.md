# Database

Using AWS RDS PostgreSQL (not a Kubernetes StatefulSet).

RDS endpoint is injected via app-secret:
  kubectl create secret generic app-secret \
    --from-literal=DATABASE_URL=postgresql://user:pass@rds-endpoint:5432/ecommerce \
    --namespace=ecommerce-dev

RDS setup:
- Engine: PostgreSQL 15
- Instance: db.t3.micro (dev)
- VPC: same as EKS cluster
- Security group: allow port 5432 from EKS node group SG
