output "lb_controller_status" {
  value = helm_release.lb_controller.status
}

output "cluster_autoscaler_status" {
  value = helm_release.cluster_autoscaler.status
}

output "external_secrets_status" {
  value = helm_release.external_secrets.status
}