variable "aws_region" {
  description = "Region details of Aws"
  type        = string
}

variable "project" {
  description = "Project name — used as a prefix in all resource names and tags"
  type        = string
  default     = "sagar-eks"
}

variable "environment" {
  description = "Environment name (dev / staging / prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in subnet tags for ALB and node discovery"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "single_nat_gateway" {
  description = "true = one NAT GW (dev cost saving) | false = one per AZ (prod HA)"
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "List of AZs — must have 3 entries"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "Exactly 3 public subnet CIDRs required (one per AZ)."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 3
    error_message = "Exactly 3 private subnet CIDRs required (one per AZ)."
  }
}