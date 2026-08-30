terraform {
  required_version = ">= 1.6.0"

  # HCP Terraform (formerly Terraform Cloud) owns and locks the state. Replace
  # this organization name before running `terraform init`.
  cloud {
    organization = "REPLACE_WITH_TFC_ORGANIZATION"

    workspaces {
      name = "voting-application-production"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
