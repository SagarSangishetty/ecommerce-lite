# ─────────────────────────────────────────────────────────────────────────────
# HELM MODULE
#
# Deploys cluster add-ons via Helm charts.
# Each release:
#   1. Creates a Kubernetes namespace (if needed)
#   2. Installs the chart with specific values
#   3. Annotates the ServiceAccount with the IRSA role ARN
#      so the pod can assume the correct AWS IAM role
# ─────────────────────────────────────────────────────────────────────────────

# ─── Namespace: external-secrets ──────────────────────────────────────────────
# kube-system already exists — only external-secrets needs to be created
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE 1 — AWS Load Balancer Controller
#
# Watches for Ingress resources and creates ALBs in AWS automatically.
# Without this, Ingress objects sit unprocessed — no ALB is created.
# ═══════════════════════════════════════════════════════════════════════════════
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"   # pin chart version for reproducibility

  # clusterName is mandatory — controller uses it to tag AWS resources
  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  # Tell the chart not to create a new SA — we manage it via serviceAccount.*
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # This annotation is what enables IRSA — pod gets AWS credentials
  # by assuming this role via the OIDC token on its ServiceAccount
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.lb_controller_role_arn
  }

  # Run 2 replicas for HA — if one pod restarts, ALB management continues
  set {
    name  = "replicaCount"
    value = "2"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE 2 — Cluster Autoscaler
#
# Monitors pending pods. If pods can't be scheduled due to insufficient
# nodes, it increases the node group desired count. If nodes are
# underutilised for 10 minutes, it scales down.
# ═══════════════════════════════════════════════════════════════════════════════
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # IRSA annotation — same pattern as LB controller
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.cluster_autoscaler_role_arn
  }

  # Skip nodes that have system pods — prevents evicting critical components
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "true"
  }

  # Wait 10 min before scaling down an underutilised node
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE 3 — External Secrets Operator
#
# Watches ExternalSecret CRDs. When one is created, ESO fetches the
# value from AWS Secrets Manager and creates/updates a K8s Secret.
# Your app pods reference the K8s Secret normally — they never talk
# to AWS directly.
# ═══════════════════════════════════════════════════════════════════════════════
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name
  version    = "0.9.19"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  # IRSA annotation
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_secrets_role_arn
  }

  # Install CRDs automatically — ExternalSecret, SecretStore, ClusterSecretStore
  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.external_secrets]
}