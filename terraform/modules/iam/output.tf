output "lb_controller_role_arn" {
  description = "LB Controller role ARN — annotate its ServiceAccount with this"
  value       = aws_iam_role.lb_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler role ARN"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "external_secrets_role_arn" {
  description = "External Secrets Operator role ARN"
  value       = aws_iam_role.external_secrets.arn
}