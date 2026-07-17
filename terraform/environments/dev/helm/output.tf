output "lb_controller_status" {
  value = helm_release.lb_controller.status
}

output "cluster_autoscaler_status" {
  value = helm_release.cluster_autoscaler.status
}

output "external_secrets_status" {
  value = helm_release.external_secrets.status
}

output "observability_namespace" {
  value = kubernetes_namespace.observability.metadata[0].name
}

output "observability_storage_class" {
  value = kubernetes_storage_class_v1.observability_gp3.metadata[0].name
}

output "kube_prometheus_stack_status" {
  value = helm_release.kube_prometheus_stack.status
}
