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

variable "github_repository" {
  description = "GitHub repository in owner/name form permitted to deploy from protected environments."
  type        = string
  default     = "fredritchie/voting_app"
}

variable "github_oidc_subject_prefix" {
  description = "Exact OIDC subject prefix reported by GitHub for the repository, including immutable owner and repository IDs when configured."
  type        = string
  default     = "repo:fredritchie@130365973/voting_app@1351196751"
}

variable "github_actions_role_name" {
  description = "Name of the IAM role assumed by the deployment workflow."
  type        = string
  default     = "github-actions-voting-app"
}

variable "ecr_repository_prefix" {
  description = "ECR repository path prefix used by the application images."
  type        = string
  default     = "voting-app"
}

variable "eks_cluster_name" {
  description = "EKS cluster the GitHub Actions deployment role may discover."
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
