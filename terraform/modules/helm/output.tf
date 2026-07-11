output "lb_controller_status" {
  description = "LB Controller helm release status"
  value       = helm_release.lb_controller.status
}

output "cluster_autoscaler_status" {
  description = "Cluster Autoscaler helm release status"
  value       = helm_release.cluster_autoscaler.status
}

output "external_secrets_status" {
  description = "External Secrets Operator helm release status"
  value       = helm_release.external_secrets.status
}