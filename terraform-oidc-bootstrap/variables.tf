variable "aws_region" {
  description = "AWS region used by the bootstrap provider. IAM resources are global."
  type        = string
  default     = "ap-south-1"
}

variable "hcp_terraform_organization" {
  description = "Exact HCP Terraform organization name."
  type        = string
  default     = "ritchie-corp"
}

variable "hcp_terraform_project" {
  description = "Exact, case-sensitive HCP Terraform project name containing the workspace."
  type        = string
}

variable "hcp_terraform_workspace" {
  description = "Exact, case-sensitive HCP Terraform workspace name."
  type        = string
  default     = "Voting_app_CLI"
}

variable "role_name" {
  description = "Name of the AWS IAM role assumed by HCP Terraform runs."
  type        = string
  default     = "hcp-terraform-voting-app"
}

variable "application_role_name_prefix" {
  description = "Prefix of IAM roles the application Terraform configuration may manage and pass to AWS services."
  type        = string
  default     = "voting-app-production"
}

variable "tags" {
  description = "Tags applied to the OIDC provider, role, and policy."
  type        = map(string)
  default = {
    Application = "voting-app"
    ManagedBy   = "Terraform"
    Purpose     = "HCP-Terraform-OIDC"
  }
}
