terraform {
  required_version = "1.16.0"

  cloud {

    organization = "ritchie-corp"

    workspaces {
      name = "Voting_app_CLI"
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
