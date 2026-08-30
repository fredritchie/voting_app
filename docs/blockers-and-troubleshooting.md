# Project Blockers and Troubleshooting

This document lists common blockers encountered while provisioning and deploying the voting application. Start with the error message, verify the likely cause, and then apply the suggested resolution.

## Terraform and HCP Terraform

| Blocker | Likely cause | Resolution |
|---|---|---|
| `Unsupported Terraform Core version` | The local or CI Terraform version does not satisfy `required_version`. | Install Terraform `1.16.0`, or intentionally update the version constraint after testing compatibility. Keep local, CI, and HCP workspace versions aligned. |
| `No value for required variable` | Required values such as `aws_region` or `eks_public_access_cidrs` are not available to the remote HCP run. | Add them as HCP workspace Terraform variables, commit a non-sensitive `*.auto.tfvars` file, or pass them through `TF_VAR_*`. Do not commit secrets. |
| `Value for undeclared variable` | A `tfvars` file contains a key without a matching `variable` block. | Remove the unused key or declare the variable if Terraform actually needs it. HCP workspace/project selection belongs in the Terraform `cloud` block or CLI configuration, not an unrelated `tfvars` value. |
| `terraform fmt -check` exits with code 3 | One or more Terraform files are not formatted. | Run `terraform fmt -recursive terraform terraform-oidc-bootstrap`, inspect the changes, and commit the formatted files. |
| Saved plan has no changes | HCP Terraform produced a plan with zero changes, but CI still attempted to apply it. | Capture `terraform plan -detailed-exitcode` and run apply only when the exit code is `2`. Treat exit code `0` as a successful no-op. |
| HCP run cannot access AWS | Dynamic AWS credentials are missing or the IAM trust policy does not match the HCP organization, project, workspace, or run phase. | Configure `TFC_AWS_PROVIDER_AUTH=true` and the appropriate HCP AWS role ARN in the workspace. Verify the AWS OIDC provider and IAM trust-policy claims. Avoid long-lived access keys. |

## AWS IAM and OIDC

| Blocker | Likely cause | Resolution |
|---|---|---|
| OIDC provider returns `EntityAlreadyExists` | The GitHub Actions OIDC provider already exists in the AWS account. | Import the existing provider into the bootstrap state or reference it as a data source. Do not attempt to create a second provider for the same URL. |
| GitHub Actions cannot call `AssumeRoleWithWebIdentity` | The IAM role trust policy does not match the repository, branch, or GitHub environment subject claim. | Verify the provider URL, audience `sts.amazonaws.com`, repository name, branch/environment subject, and the exact role ARN configured in GitHub. |
| EKS node group creation is missing `iam:GetRole` | The Terraform execution role cannot check the EKS node-group service-linked role. | Grant the bootstrap/HCP role `iam:GetRole` for the required role, along with the permissions needed to create the defined EKS resources. |
| EKS add-on fails with `iam:PassRole` | Terraform creates an add-on that uses an IAM role but cannot pass that role to EKS. | Grant narrowly scoped `iam:PassRole` access to the CloudWatch agent role and restrict the service where practical. |
| CloudWatch dashboard creation is denied | The Terraform role lacks dashboard permissions. | Grant `cloudwatch:PutDashboard` and the corresponding read/delete permissions required to manage the dashboard lifecycle. |

## GitHub Actions and Container Images

| Blocker | Likely cause | Resolution |
|---|---|---|
| Deployment waits indefinitely for a self-hosted runner | No online runner has all requested labels. | Use `ubuntu-latest` when the EKS endpoint and deployment path are reachable publicly, or register and maintain a correctly labelled self-hosted runner. |
| `docker/login-action` reports `Username and password required` | Legacy Docker sample workflows enable Docker Hub but the Docker Hub secrets are unset. | Remove or disable the obsolete `call-docker-build-*.yaml` workflows when ECR is the selected registry. The main pipeline already authenticates to ECR through AWS OIDC. |
| Node runtime deprecation warning | A third-party or old action still uses a deprecated Node runtime. | Upgrade the action to a maintained major version or remove the obsolete workflow. Do not rely on the temporary insecure-version compatibility flag as a permanent fix. |
| ECR push is denied | The GitHub deployment role lacks ECR permissions or is assuming the wrong role. | Verify OIDC authentication and allow the required ECR authorization, upload, layer, and image operations for the three application repositories. |
| Image exists but deployment uses an old image | The manifest tag, deployment annotation, or pull policy was not updated. | Deploy immutable commit-SHA tags, update all three images, and wait for each Kubernetes rollout to finish. |

## EKS and Kubernetes Access

| Blocker | Likely cause | Resolution |
|---|---|---|
| `kubectl` says the client must provide credentials | The kubeconfig identity has no valid AWS credentials, or the IAM principal is not authorized for the cluster. | Authenticate to AWS, run `aws eks update-kubeconfig`, and verify the caller with `aws sts get-caller-identity`. |
| `kubectl` returns `Unauthorized` after updating kubeconfig | The current IAM user/role does not have an EKS access entry or Kubernetes RBAC access. | Add an EKS access entry and associate the minimum required EKS access policy. Ensure the ARN matches the identity used locally or in CI. |
| GitHub can assume its AWS role but cannot deploy to EKS | AWS IAM authentication succeeds, but the GitHub role has no EKS access entry or cluster policy association. | Create an EKS access entry for the GitHub role and associate an appropriate cluster access policy. |
| Staging is not publicly accessible | Staging uses internal test access and intentionally has no public load balancer. | Use `kubectl port-forward` after obtaining cluster access. Add a staging ingress/load balancer only if public staging access is an explicit requirement. |
| Production load balancer has no endpoint immediately | AWS load-balancer provisioning and Kubernetes reconciliation are asynchronous. | Wait for `kubectl get service -n production` to show an external hostname, then verify the service endpoints, pods, health checks, and security groups. |

## Monitoring and Logging

| Blocker | Likely cause | Resolution |
|---|---|---|
| Node CPU and memory dashboard widgets are empty | The CloudWatch search schema does not match the emitted Container Insights dimensions. | Query node metrics with `ClusterName`, `NodeName`, and `InstanceId`. Confirm the observability add-on is active and metrics exist in the `ContainerInsights` namespace. |
| Container Insights has no metrics or logs | The EKS observability add-on is unhealthy, Pod Identity is incomplete, or the agent role lacks permissions. | Check the add-on status, CloudWatch agent pods, Pod Identity association, log groups, and `CloudWatchAgentServerPolicy` attachment. |
| Log-derived application metrics remain at zero | The expected application text is absent from the configured Container Insights log group or does not match the filter pattern. | Confirm application logs reach the log group and test the filter pattern against actual messages. |

## Safe Operator Checklist

Before running a production deployment:

1. Confirm the current branch, commit SHA, and target GitHub environment.
2. Confirm HCP Terraform variables and dynamic AWS credentials are configured.
3. Run Terraform formatting, validation, and a reviewed remote plan.
4. Confirm GitHub OIDC assumes the intended AWS role.
5. Confirm the EKS cluster, node group, and observability add-ons are healthy.
6. Confirm the vote, result, and worker images use the same immutable commit tag.
7. Confirm staging remains private and production services alone use public load balancers.
8. Verify deployment rollouts, service endpoints, CloudWatch dashboards, and recent logs.
9. Use the Terraform destroy workflow only after reviewing the destroy plan and confirming data-retention requirements.

