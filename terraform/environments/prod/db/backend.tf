terraform {
  backend "s3" {
    bucket         = "ecommerce-lite-tf-state-169976490560"
    key            = "prod/db/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
  }
}