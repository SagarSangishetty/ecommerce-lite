variable "project" {
  type    = string
  default = "sagar-eks"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type = string


}

variable "observability_namespace" {
  type    = string
  default = "observability"
}

variable "observability_storage_class_name" {
  type    = string
  default = "ebs-gp3"
}

variable "grafana_admin_secret_remote_key" {
  type    = string
  default = "dev/ecommerce/observability/grafana"
}
