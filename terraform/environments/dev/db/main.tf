# main.tf — Dev RDS environment
# Calls the RDS module with dev-specific values
# Reads VPC outputs from remote state
# Password injected via environment variable — not tfvars

# ── READ VPC OUTPUTS ──────────────────────────────────────────
# VPC must be applied before RDS
# This reads vpc_id and subnet_ids from VPC state file

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/eks/terraform.tfstate"
    region = "us-east-1"
  }
}

# ── CALL RDS MODULE ───────────────────────────────────────────

module "rds" {
  source = "../../../modules/db"

  # Pass all variables from tfvars
  db_identifier             = var.db_identifier
  db_engine                 = var.db_engine
  db_engine_version         = var.db_engine_version
  db_instance_class         = var.db_instance_class
  db_allocated_storage      = var.db_allocated_storage
  db_max_allocated_storage  = var.db_max_allocated_storage
  db_storage_type           = var.db_storage_type
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  multi_az                  = var.multi_az
  publicly_accessible       = var.publicly_accessible
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  environment               = var.environment
  project                   = var.project

  # Network values from VPC remote state
  # These are not in tfvars — they come from VPC outputs
  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # EKS node group security group — allows EKS pods to reach RDS
  # Read from EKS remote state once EKS is provisioned
  # For now reference directly — update after EKS is created
  allowed_security_group_id = data.terraform_remote_state.eks.outputs.eks_node_sg_id
}
