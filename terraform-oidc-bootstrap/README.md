# HCP Terraform AWS OIDC bootstrap

This standalone Terraform configuration creates:

- the `app.terraform.io` AWS IAM OIDC provider;
- a role that only trusts the configured HCP Terraform organization, project,
  workspace, and the `plan`/`apply` run phases;
- an infrastructure policy for the VPC, EBS, EKS, ECR, RDS, and CloudWatch Logs
  resources in `../terraform`;
- scoped IAM role management and `iam:PassRole` access for application roles;
- the permissions RDS needs to create its managed master-password secret.
- an environment-scoped deployment role using the account's existing GitHub
  Actions OIDC provider;
- ECR push and EKS discovery permissions for the deployment workflow.

## Bootstrap

This directory intentionally has no HCP Terraform `cloud` block. Run it once
with an existing AWS administrator identity because the OIDC role cannot create
itself.

```sh
cd terraform-oidc-bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and make the organization, project, and workspace names
match HCP Terraform exactly. Then authenticate to the target AWS account and run:

```sh
aws sts get-caller-identity
terraform init
terraform plan
terraform apply
```

Do not commit `terraform.tfvars` or the local state. Both are ignored by the
repository `.gitignore`.

## Configure the HCP Terraform workspace

After apply, run:

```sh
terraform output hcp_terraform_workspace_environment_variables
```

Add both returned values to the HCP Terraform workspace as **Environment
variables**, not Terraform variables:

- `TFC_AWS_PROVIDER_AUTH=true`
- `TFC_AWS_RUN_ROLE_ARN=<hcp_terraform_role_arn output>`

The values are identifiers, not secrets, so they do not need the Sensitive flag.

Also obtain the GitHub Actions role:

```sh
terraform output github_actions_role_arn
```

Add this ARN as the `AWS_ROLE_ARN` variable in both the `staging` and
`production` GitHub environments. Set the same ARN as the HCP Terraform
**Terraform variable** `github_actions_role_arn`, then apply the main
configuration so EKS grants the role Kubernetes API access.

## Existing OIDC provider

An AWS account can already have the HCP Terraform OIDC provider. If
`terraform plan` reports that it exists, import it rather than creating a
duplicate:

```sh
terraform import aws_iam_openid_connect_provider.hcp_terraform \
  arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/app.terraform.io
```

The GitHub Actions provider is shared with another stack in this account, so
this configuration reads it as a data source and does not modify or import it.

The service actions intentionally use broad wildcards because Terraform must
create, read, update, and delete these resource types. IAM role management and
role passing remain restricted to `application_role_name_prefix`.
