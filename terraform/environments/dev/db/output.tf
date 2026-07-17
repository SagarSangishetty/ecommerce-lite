# ── OUTPUTS ───────────────────────────────────────────────────
# Expose module outputs at environment level
# So other state files can read them

output "db_endpoint" {
  value = module.rds.db_endpoint
}

output "db_host" {
  value = module.rds.db_host
}

output "db_port" {
  value = module.rds.db_port
}

output "db_name" {
  value = module.rds.db_name
}

output "rds_security_group_id" {
  value = module.rds.rds_security_group_id
}