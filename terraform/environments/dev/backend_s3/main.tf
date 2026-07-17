provider "aws" {
    region = "us-east-1"
  
}


module "terraform_backend" {
    source = "../../../modules/backend_s3"
    bucket_name = var.bucket_name
    environment = var.environment
 
}