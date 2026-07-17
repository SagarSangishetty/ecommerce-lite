# ─── Read outputs from EKS state file ─────────────────────────────────────────
# Since EKS is a separate terraform root with its own state,
# we read its outputs using remote_state data source
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/eks/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─── Read outputs from IAM state file ─────────────────────────────────────────
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/iam/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# ─── AWS provider ─────────────────────────────────────────────────────────────

locals {
  grafana_admin_secret_name = "grafana-admin"
}

provider "kubectl" {
  # reuse the same connection config as your existing kubernetes/helm providers
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ─── Kubernetes provider ──────────────────────────────────────────────────────
# Authenticates using outputs read from EKS remote state
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name,
      "--region", var.aws_region
    ]
  }
}

# ─── Helm provider ────────────────────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name,
        "--region", var.aws_region
      ]
    }
  }
}

# ─── Namespace: external-secrets ──────────────────────────────────────────────
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.observability_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      environment                    = var.environment
      project                        = var.project
    }
  }
}

resource "kubernetes_storage_class_v1" "observability_gp3" {
  metadata {
    name = var.observability_storage_class_name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      environment                    = var.environment
      project                        = var.project
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# ─── Helm Release: AWS Load Balancer Controller ───────────────────────────────

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.eks.outputs.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # Role ARN read from IAM remote state
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.iam.outputs.lb_controller_role_arn
  }

  # Fix — explicitly pass VPC ID, skip metadata discovery

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.vpc.outputs.vpc_id
  }

  # Fix — explicitly pass region
  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "replicaCount"
    value = "2"
  }
}

# ─── Helm Release: Cluster Autoscaler ─────────────────────────────────────────
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = data.terraform_remote_state.eks.outputs.cluster_name
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

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.iam.outputs.cluster_autoscaler_role_arn
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "true"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }
}

# ─── Helm Release: External Secrets Operator ──────────────────────────────────
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

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.iam.outputs.external_secrets_role_arn
  }

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.external_secrets]
}

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secret-store"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = kubernetes_namespace.external_secrets.metadata[0].name
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "grafana_admin_external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.grafana_admin_secret_name
      namespace = kubernetes_namespace.observability.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secret-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = local.grafana_admin_secret_name
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "admin-user"
          remoteRef = {
            key      = var.grafana_admin_secret_remote_key
            property = "admin-user"
          }
        },
        {
          secretKey = "admin-password"
          remoteRef = {
            key      = var.grafana_admin_secret_remote_key
            property = "admin-password"
          }
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.observability
  ]
}

resource "helm_release" "kube_prometheus_stack" {
  name              = "kube-prometheus-stack"
  repository        = "https://prometheus-community.github.io/helm-charts"
  chart             = "kube-prometheus-stack"
  namespace         = kubernetes_namespace.observability.metadata[0].name
  version           = "87.15.1"
  atomic            = true
  cleanup_on_fail   = true
  dependency_update = true
  timeout           = 900
  wait              = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }

      defaultRules = {
        create = true
        rules = {
          etcd                   = false
          kubeControllerManager  = false
          kubeSchedulerAlerting  = false
          kubeSchedulerRecording = false
        }
      }

      kubeEtcd = {
        enabled = false
      }

      kubeControllerManager = {
        enabled = false
      }

      kubeScheduler = {
        enabled = false
      }

      grafana = {
        enabled = true

        admin = {
          existingSecret = local.grafana_admin_secret_name
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }

        service = {
          type = "ClusterIP"
        }

        ingress = {
          enabled = false
        }

        persistence = {
          enabled          = true
          storageClassName = kubernetes_storage_class_v1.observability_gp3.metadata[0].name
          size             = "5Gi"
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      prometheus = {
        service = {
          type = "ClusterIP"
        }

        prometheusSpec = {
          replicas      = 1
          retention     = "15d"
          retentionSize = "8GB"

          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          probeSelectorNilUsesHelmValues          = false
          ruleSelectorNilUsesHelmValues           = false
          scrapeConfigSelectorNilUsesHelmValues   = false

          # Watch ServiceMonitors only in ecommerce-dev
          serviceMonitorNamespaceSelector = {
            matchNames = [
              "ecommerce-dev"
             ]
          }

          # Watch PrometheusRules only in ecommerce-dev
          ruleNamespaceSelector = {
            matchNames = [
              "ecommerce-dev"
            ]
          }

          # Watch PodMonitors only in ecommerce-dev
          podMonitorNamespaceSelector = {
            matchNames = [
              "ecommerce-dev"
            ]
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class_v1.observability_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }

          resources = {
            requests = {
              cpu    = "250m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          replicas  = 1
          retention = "120h"

          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class_v1.observability_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }

          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }

      prometheusOperator = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      "kube-state-metrics" = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      "prometheus-node-exporter" = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.external_secrets,
      helm_release.lb_controller,
    kubectl_manifest.grafana_admin_external_secret,
    kubernetes_storage_class_v1.observability_gp3
  ]
}


# ─── Helm Release: Elasticsearch (single-node, dev-sized) ────────────────────
resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = "8.5.1"
  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  wait            = true

  values = [
    yamlencode({
      replicas   = 1
      minimumMasterNodes = 1

      esJavaOpts = "-Xmx1g -Xms1g"

      esConfig = {
        "elasticsearch.yml" = <<-EOT
          xpack.security.enabled: false
          xpack.security.http.ssl.enabled: false
          xpack.security.transport.ssl.enabled: false
        EOT
      }

      resources = {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "3Gi"
        }
      }

      volumeClaimTemplate = {
        storageClassName = kubernetes_storage_class_v1.observability_gp3.metadata[0].name
        accessModes       = ["ReadWriteOnce"]
        resources = {
          requests = {
            storage = "20Gi"
          }
        }
      }

      # Single-node dev cluster — disable strict bootstrap checks that assume
      # multi-node HA setups
      clusterHealthCheckParams = "wait_for_status=yellow&timeout=1s"

      antiAffinity = "soft"
    })
  ]

  depends_on = [
    helm_release.lb_controller,
    kubernetes_storage_class_v1.observability_gp3
  ]
}

# ─── Helm Release: Kibana ──────────────────────────────────────────────────────
resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = "8.5.1"
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600
  wait            = true

  values = [
    yamlencode({
      elasticsearchHosts = "https://elasticsearch-master:9200"

      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      service = {
        type = "ClusterIP"
      }
    })
  ]

  depends_on = [
    helm_release.elasticsearch
  ]
}

# ─── Helm Release: Fluent Bit (log shipper, DaemonSet) ────────────────────────
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = "0.57.9"
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300
  wait            = true

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }

      config = {
        filters = <<-EOT
          [FILTER]
              Name                kubernetes
              Match               kube.*
              Merge_Log           Off
              Keep_Log            On
              K8S-Logging.Parser  On
              K8S-Logging.Exclude On
              Labels              Off
              Annotations         Off
        EOT

        outputs = <<-EOT
          [OUTPUT]
              Name                  es
              Match                 kube.*
              Host                  elasticsearch-master
              Port                  9200
              tls                   On
              tls.Verify            Off
              HTTP_User             elastic
              HTTP_Passwd           ghpUHnXA77cRmq1f
              Logstash_Format       On
              Logstash_Prefix       ecommerce-lite
              Retry_Limit           False
              Suppress_Type_Name    On
              Trace_Error           On
              Trace_Output          On
        EOT
      }
    })
  ]

  depends_on = [
    helm_release.elasticsearch
  ]
}

# ─── Helm Release: Jaeger (all-in-one, dev-sized): ────────────────────

resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = "4.11.1"
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300
  wait            = true

  values = [
    yamlencode({
      allInOne = {
        enabled = true
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      storage = {
        type = "badger"
      }

      provisionDataStore = {
        cassandra     = false
        elasticsearch = false
      }

      collector = {
        enabled = false
      }
      query = {
        enabled = false
      }
      agent = {
        enabled = false
      }
    })
  ]

  depends_on = [
    helm_release.lb_controller
  ]
}

#OTel Collector (receives OTLP on 4317 from your apps, forwards to Jaeger):

resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = "0.165.0"
  atomic          = true
  cleanup_on_fail = true
  timeout         = 300
  wait            = true

  values = [
    yamlencode({
      mode = "deployment"

      fullnameOverride = "otel-collector"

      image = {
      repository = "otel/opentelemetry-collector-contrib"
      tag        = "0.116.1"
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }

      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
        }

        exporters = {
          "otlp/jaeger" = {
            endpoint = "jaeger:4317"
            tls = {
              insecure = true
            }
          }
        }

        service = {
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              exporters  = ["otlp/jaeger"]
            }
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.jaeger
  ]
}