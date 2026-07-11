terraform {
  backend "s3" {
    bucket         = "ecommerce-lite-tf-state-169976490560"
    key            = "dev/eks/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
  }
}