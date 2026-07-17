provider "aws" {
  region = "us-east-1"
  
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "ecommerce-lite-tf-state-169976490560"
    key    = "dev/eks/terraform.tfstate"
    region = "us-east-1"
  }
}

module "iam" {
  source = "../../../modules/iam"

  project           = var.project
  environment       = var.environment
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.eks.outputs.oidc_provider_url
}