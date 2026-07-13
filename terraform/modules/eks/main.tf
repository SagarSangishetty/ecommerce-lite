# ─────────────────────────────────────────────────────────────────────────────
# EKS MODULE
#
# Creates:
#   1. IAM role for EKS control plane
#   2. IAM role for worker nodes
#   3. Security groups (cluster + node)
#   4. EKS cluster
#   5. OIDC provider (enables IRSA in Phase 4)
#   6. Managed node group
#   7. EKS managed add-ons
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Module = "eks"
  }
}

# ─── 1. IAM Role — EKS Control Plane ─────────────────────────────────────────
# The EKS service assumes this role to manage AWS resources on your behalf
# (ENIs, security groups, NLBs for the API server)
resource "aws_iam_role" "cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── 2. IAM Role — Worker Nodes ───────────────────────────────────────────────
# EC2 instances assume this role to:
#   - Register themselves with the cluster (EKSWorkerNodePolicy)
#   - Configure pod networking via VPC CNI (EKS_CNI_Policy)
#   - Pull container images from ECR (EC2ContainerRegistryReadOnly)
resource "aws_iam_role" "node_group" {
  name = "${local.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── 3. Security Groups ───────────────────────────────────────────────────────

# Cluster SG — attached to the EKS API server
resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS cluster API server security group"
  vpc_id      = var.vpc_id

  # Allow inbound 443 from your machine / CI / VPN
  ingress {
    description = "kubectl and CI access to API server"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound — control plane needs to reach nodes and AWS APIs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

# Node SG — attached to all worker node EC2 instances
resource "aws_security_group" "node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id

  # Nodes talk to each other — pod-to-pod, kubelet, CNI
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Control plane reaches nodes for kubelet (10250) and webhooks
  ingress {
    description             = "Control plane to node kubelet and webhooks"
    from_port               = 1025
    to_port                 = 65535
    protocol                = "tcp"
    security_groups         = [aws_security_group.cluster.id]
  }

  # Control plane reaches nodes on 443 (metrics, webhooks)
  ingress {
    description             = "Control plane to node 443"
    from_port               = 443
    to_port                 = 443
    protocol                = "tcp"
    security_groups         = [aws_security_group.cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-sg"
    # Cluster Autoscaler and Karpenter discover nodes via this tag
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Allow nodes to reach API server — completes the bidirectional trust
resource "aws_security_group_rule" "node_to_cluster" {
  description              = "Nodes to API server 443"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# ─── 4. EKS Cluster ───────────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true  # set false in prod, access via VPN/bastion
  }

  # Enterprise: enable all control plane log types for audit
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Cluster must be created after IAM role policy is attached
  # Without this, EKS creation fails with permissions error
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })
}

# ─── 5. OIDC Provider ─────────────────────────────────────────────────────────
# Enables IRSA — pods get individual IAM roles via service account annotations
# The thumbprint is the TLS certificate fingerprint of the OIDC issuer endpoint
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

# ─── EBS CSI Driver IAM Role (IRSA) ───────────────────────────────────────────
# This role allows the EBS CSI driver pods to manage EBS volumes
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${local.name_prefix}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ebs-csi-driver-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}



# ─── 6. Managed Node Group ────────────────────────────────────────────────────

resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-node-lt"

  vpc_security_group_ids = [aws_security_group.node.id]

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-general-node"
    })
  }
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-general"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-general-node"
  })
}

# ─── 7. EKS Managed Add-ons ───────────────────────────────────────────────────
# most_recent = true lets AWS pick the latest version compatible with
# your cluster version — safe for managed add-ons

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on    = [aws_eks_node_group.general]
  tags          = local.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"   
  depends_on    = [aws_eks_node_group.general]
  tags          = local.common_tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"   
  depends_on    = [aws_eks_node_group.general]
  tags          = local.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.35.0-eksbuild.1"  # Use latest compatible version
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [
    aws_eks_node_group.general,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy
  ]
  
  tags = local.common_tags
}
