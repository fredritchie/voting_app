# Project challenges and Troubleshooting

This file contains some common issues I faced while deploying the voting application and how I fixed them.

## Terraform and HCP Terraform

### Unsupported Terraform version

This happened because local Terraform version and HCP Terraform version was different.

I fixed it by using Terraform `1.16.0` in local, CI and HCP.

### No value for required variable

Some variables like `aws_region` and `eks_public_access_cidrs` was missing in HCP Terraform.

I added them in the HCP workspace variables.

### Undeclared variable

This happens when a value is given in `tfvars` but the variable is not created in `variables.tf`.

I removed unused values or added the missing variable.

### terraform fmt failed

If `terraform fmt -check` gives exit code 3, some files are not formatted.

```bash
terraform fmt -recursive
```

### HCP cannot access AWS

This was mainly because AWS dynamic credentials or IAM trust policy was not correct.

I added:

```text
TFC_AWS_PROVIDER_AUTH=true
```

and configured the correct AWS role ARN in HCP.

## AWS IAM and OIDC

### OIDC provider already exists

Terraform showed `EntityAlreadyExists` because GitHub OIDC provider was already created.

I used the existing provider instead of creating new one.

### GitHub AssumeRoleWithWebIdentity failed

The IAM trust policy was not matching with GitHub repo, branch or environment.

I checked the repository name, branch, audience and role ARN.

### IAM permission errors

For EKS and CloudWatch I faced few permission errors like:

```text
iam:GetRole
iam:PassRole
cloudwatch:PutDashboard
```

I added only the required permissions to Terraform role.

## GitHub Actions and ECR

### Self-hosted runner waiting

The workflow was waiting because no self-hosted runner was online.

I changed it to:

```yaml
runs-on: ubuntu-latest
```

where possible.

### Docker login error

Some old workflows was trying to login to Docker Hub.

Since this project is using ECR, I removed those old Docker workflows.

### ECR push denied

GitHub role was missing ECR permissions.

I checked the OIDC role and added required ECR push permissions.

### Old image deployed

Sometimes Kubernetes was still using old image.

I started using Git commit SHA as image tag for `vote`, `result` and `worker`.

## EKS and Kubernetes

### kubectl credential error

First I checked AWS identity:

```bash
aws sts get-caller-identity
```

Then updated kubeconfig:

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### kubectl Unauthorized

The IAM role did not have EKS cluster access.

I created an EKS access entry and added required cluster access policy.

### GitHub cannot deploy to EKS

GitHub can login to AWS but still need access inside EKS.

I added the GitHub IAM role as an EKS access entry.

### Staging not public

Staging is kept private, so I use `kubectl port-forward` for testing.

Production only uses public LoadBalancer.

## Monitoring

### CPU and memory graphs empty

CloudWatch dashboard was using wrong Container Insights dimensions.

I checked metrics using:

```text
ClusterName
NodeName
InstanceId
```

### No Container Insights logs

I checked CloudWatch add-on, agent pods, Pod Identity and IAM permissions.

