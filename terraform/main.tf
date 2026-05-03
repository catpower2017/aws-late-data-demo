
terraform {

  required_version = ">= 1.7.0"

  required_providers {

    aws = {

      source  = "hashicorp/aws"

      version = "~> 5.90"

    }

  }

  # No backend = local state file (fine for demo)

}

provider "aws" {

  region = var.aws_region

  default_tags {

    tags = {

      Project     = "late-data-demo"

      Environment = var.environment

      ManagedBy   = "terraform"

    }

  }

}
