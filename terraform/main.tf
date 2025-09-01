terraform {
  required_version = ">= 1.13.1"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# kubernetes & helm providers will be configured after EKS is created (using data resources / local exec),
# so they are declared here but configured later in workflow if needed.
