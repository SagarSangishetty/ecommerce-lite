# main.tf
# Creates:
#   - DB subnet group (tells RDS which subnets to use)
#   - Security group (controls who can connect to RDS)
#   - RDS instance (the actual database)
#
# Password comes from variable — never hardcoded
# All resources tagged with environment and project

# ── DB SUBNET GROUP ───────────────────────────────────────────
# RDS needs to know which subnets it can use
# Always use private subnets — no public access to database

resource "aws_db_subnet_group" "this" {
  name        = "${var.db_identifier}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for ${var.db_identifier}"

  tags = {
    Name        = "${var.db_identifier}-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}


# ── SECURITY GROUP ────────────────────────────────────────────
# Controls who can connect to RDS on port 5432
# Only allows traffic from EKS node group security group
# No public internet access

resource "aws_security_group" "rds" {
  name        = "${var.db_identifier}-sg"
  description = "Security group for ${var.db_identifier} RDS instance"
  vpc_id      = var.vpc_id

  # Allow inbound PostgreSQL from EKS nodes only
  ingress {
    description     = "PostgreSQL from EKS node group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.db_identifier}-sg"
    Environment = var.environment
    Project     = var.project
  }
}


# ── RDS INSTANCE ──────────────────────────────────────────────
# The actual PostgreSQL database
# All configuration comes from variables
# Password marked sensitive — never appears in logs

resource "aws_db_instance" "this" {
  # Identity
  identifier = var.db_identifier

  # Engine
  engine         = var.db_engine
  engine_version = var.db_engine_version

  # Instance
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = var.db_storage_type
  storage_encrypted     = true    # always encrypt at rest

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # Backup
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  # Final snapshot name — only used when skip_final_snapshot = false
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.db_identifier}-final-snapshot"

  # Auto minor version upgrades during maintenance window
  auto_minor_version_upgrade = true

  tags = {
    Name        = var.db_identifier
    Environment = var.environment
    Project     = var.project
  }

  # Prevent accidental destroy
  lifecycle {
    prevent_destroy = false    # overridden per environment via deletion_protection
  }
}