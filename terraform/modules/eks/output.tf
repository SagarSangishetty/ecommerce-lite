output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint — used by helm and kubernetes providers"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate — used by helm and kubernetes providers"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — passed to IRSA role creation in Phase 4"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL without https:// — used in IAM trust policies"
  value       = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

output "node_security_group_id" {
  description = "Node SG ID — needed for adding rules from other modules"
  value       = aws_security_group.node.id
}

output "cluster_security_group_id" {
  description = "Cluster SG ID"
  value       = aws_security_group.cluster.id
}

output "node_role_arn" {
  description = "Node IAM role ARN"
  value       = aws_iam_role.node_group.arn
}