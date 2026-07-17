# Declares all variables this environment accepts
# Values come from terraform.tfvars
# db_password comes from environment variable — never in tfvars

variable "db_identifier"             { type = string }
variable "db_engine"                 { type = string }
variable "db_engine_version"         { type = string }
variable "db_instance_class"         { type = string }
variable "db_allocated_storage"      { type = number }
variable "db_max_allocated_storage"  { type = number }
variable "db_storage_type"           { type = string }
variable "db_name"                   { type = string }
variable "db_username"               { type = string }
variable "db_password" {       
  type      = string                   ###export TF_VAR_db_password="postgress"##
  sensitive = true
}
variable "multi_az"                  { type = bool }
variable "publicly_accessible"       { type = bool }
variable "backup_retention_period"   { type = number }
variable "backup_window"             { type = string }
variable "maintenance_window"        { type = string }
variable "deletion_protection"       { type = bool }
variable "skip_final_snapshot"       { type = bool }
variable "environment"               { type = string }
variable "project"                   { type = string }