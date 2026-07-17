provider "aws" {
  region = "us-east-1"
  
}

# environments/dev/main.tf

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}


module "eks" {
  source = "../../../modules/eks"

  project             = var.project
  environment         = var.environment
  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = data.terraform_remote_state.vpc.outputs.vpc_id        # ← from remote state
  private_subnet_ids  = data.terraform_remote_state.vpc.outputs.private_subnet_ids  # ← from remote state
  node_instance_type  = var.node_instance_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  allowed_cidr_blocks = var.allowed_cidr_blocks
}