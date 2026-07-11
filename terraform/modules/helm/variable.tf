variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — passed to LB controller chart values"
  type        = string
}

variable "aws_region" {
  description = "AWS region — passed to Cluster Autoscaler chart values"
  type        = string
}

variable "lb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  type        = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler"
  type        = string
}

variable "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator"
  type        = string
}