variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN — from eks module output"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// — from eks module output"
  type        = string
}