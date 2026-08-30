output "hcp_terraform_role_arn" {
  description = "Set this as the HCP Terraform environment variable TFC_AWS_RUN_ROLE_ARN."
  value       = aws_iam_role.hcp_terraform.arn
}

output "hcp_terraform_subject" {
  description = "OIDC subject allowed by the IAM role trust policy."
  value       = "organization:${var.hcp_terraform_organization}:project:${var.hcp_terraform_project}:workspace:${var.hcp_terraform_workspace}:run_phase:*"
}

output "hcp_terraform_workspace_environment_variables" {
  description = "Non-secret environment variables to configure in the HCP Terraform workspace."
  value = {
    TFC_AWS_PROVIDER_AUTH = "true"
    TFC_AWS_RUN_ROLE_ARN  = aws_iam_role.hcp_terraform.arn
  }
}

output "github_actions_role_arn" {
  description = "Set this as AWS_ROLE_ARN in the staging and production GitHub environments."
  value       = aws_iam_role.github_actions.arn
}
