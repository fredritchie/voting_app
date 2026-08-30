# AWS infrastructure: EKS, RDS, and HCP Terraform

This directory creates the AWS foundation for the voting application:

```text
Internet
  |-- public subnets: load balancers and NAT gateways
  |-- private subnets: EKS managed worker nodes and application pods
  `-- isolated database subnets: private RDS PostgreSQL Multi-AZ instance
```

It also creates three private ECR repositories (`vote`, `result`, and `worker`) for the application's container images.

## Before the first run

1. Create an HCP Terraform organization and a workspace named `voting-application-production`.
2. Replace `REPLACE_WITH_TFC_ORGANIZATION` in `versions.tf` with that organization name. The `cloud` block is the current HCP Terraform state integration; do not add an S3, `remote`, or other `backend` block alongside it.
3. Configure AWS credentials in the HCP Terraform workspace. Prefer HCP Terraform dynamic provider credentials with AWS IAM OIDC over long-lived access keys. The AWS identity needs permission to create the resources defined here.
4. Add `aws_region` and `eks_public_access_cidrs` as HCP Terraform workspace variables. Mark only genuinely secret values as sensitive; this configuration deliberately has no database password input.
5. For GitHub Actions deployments, apply `../terraform-oidc-bootstrap` and add its `github_actions_role_arn` output as a Terraform workspace variable with the same name. This creates an EKS access entry for the deployment role.
6. Commit this directory, connect the workspace to the repository with working directory `terraform`, and run a speculative plan before applying.

Reapply `terraform-oidc-bootstrap` after upgrading an existing deployment so
the HCP Terraform role can manage the inline least-privilege policy used by the
application database Pod Identity role.

For CLI-driven remote execution, run `terraform login`, then:

```sh
cd terraform
terraform init
terraform plan
```

For GitHub Actions, add an HCP Terraform API token as the repository secret
`TF_API_TOKEN`. The reusable `.github/workflows/terraform-apply.yml` workflow
runs this configuration remotely before the application deployment job. Keep
`aws_region`, `eks_public_access_cidrs`, and `github_actions_role_arn` configured
as Terraform variables in the HCP workspace because ignored local `.tfvars`
files are not present on a clean GitHub runner.

To grant a local IAM user or role access to inspect workloads and use
`kubectl port-forward`, add `eks_application_admin_principal_arns` as an HCL
Terraform workspace variable. For example:

```hcl
["arn:aws:iam::008971653023:user/root"]
```

Configured principals receive `AmazonEKSAdminPolicy` only in the `staging` and
`production` namespaces.

## Monitoring and centralized logging

The `amazon-cloudwatch-observability` EKS add-on runs the CloudWatch agent and
Fluent Bit. It uses EKS Pod Identity through a dedicated
`<cluster>-cloudwatch-agent` role, so telemetry credentials are not granted
to every workload on a node. The add-on sends these streams to CloudWatch Logs:

- `/aws/containerinsights/<cluster>/application`: container stdout/stderr;
- `/aws/containerinsights/<cluster>/dataplane`: kubelet, container runtime,
  kube-proxy, and VPC CNI logs;
- `/aws/containerinsights/<cluster>/host`: operating-system logs;
- `/aws/containerinsights/<cluster>/performance`: Container Insights telemetry.

Terraform applies `monitoring_log_retention_days` to all four groups; the
default is 30 days. EKS control-plane logs remain in
`/aws/eks/<cluster>/cluster`, and PostgreSQL/upgrade logs use their RDS-managed
CloudWatch log groups.

Two CloudWatch dashboards are created:

- `<cluster>-infrastructure`: EKS node health/CPU/memory, RDS CPU/connections,
  NAT traffic, and recent control-plane errors;
- `<cluster>-application`: staging/production pod counts, CPU, memory, restarts,
  vote/error log-derived metrics, log volume, and recent application errors.

Run `terraform output cloudwatch_dashboard_urls` after apply to open them. New
Container Insights series and log-derived metrics can take several minutes to
appear after the add-on becomes active. CloudWatch ingestion, dashboards,
Application Signals, and Logs Insights queries incur AWS charges.

Use [`terraform.tfvars.example`](terraform.tfvars.example) only as a non-secret local template. Never commit a real `terraform.tfvars` file.

## Design decisions

### State and credentials

- **HCP Terraform cloud integration** stores state remotely, locks it during runs, and centralizes run history. It is intentionally configured with `cloud`, not the legacy `backend "remote"` syntax.
- **No AWS keys or database password in Git.** AWS authentication belongs in workspace credentials; RDS uses `manage_master_user_password`, which creates and manages the password in AWS Secrets Manager. The secret ARN is a sensitive Terraform output.

### Network topology

- **Three Availability Zones by default** make the worker capacity and RDS deployment survive an AZ failure. The input supports two or three AZs for regions with limited availability.
- **EKS nodes live in private subnets** and have no public IPs. Public-facing AWS load balancers can be placed in the tagged public subnets, while internal load balancers use the tagged private subnets.
- **Database subnets have no default route to the internet.** RDS is private and its security group only permits TCP/5432 from the EKS private-subnet ranges.
- **One NAT gateway per AZ** provides zone-independent outbound access for private nodes, including image pulls, while avoiding a single-AZ networking failure. NAT gateways and Elastic IPs have ongoing AWS cost.
- **The EKS API has both private and restricted public access.** Private access serves workload/node traffic; the public endpoint enables tightly controlled operators and CI to use `kubectl`. `eks_public_access_cidrs` is deliberately required so an unrestricted API endpoint cannot be applied by default. For a fully private control plane, set public access to false and provide VPN, Direct Connect, or a bastion/VPC-based administration path.

### EKS and containers

- **Managed node groups** leave EC2 lifecycle operations to EKS. The default three-node baseline allows workloads to remain available while one node is being updated.
- **AWS-managed IAM policies** give nodes only the standard EKS, CNI, and ECR-read capabilities needed to join the cluster and pull images. Application-specific AWS permissions should later use IRSA/EKS Pod Identity, not the node role.
- **Control-plane logs** are sent to CloudWatch with a 30-day retention period for API/audit troubleshooting.
- **ECR repositories are immutable and scanned on push.** Immutable tags make deployments traceable and reduce accidental overwrites. Use unique image tags such as a Git commit SHA.

### RDS PostgreSQL

- **RDS PostgreSQL replaces the in-cluster `db` deployment.** The worker and result Pods use an EKS Pod Identity role to discover the RDS-managed secret, and an AWS CLI init container writes that secret to a memory-backed volume. The applications read the file at startup; the password is never committed or stored in a Kubernetes Secret object.
- **Multi-AZ, encrypted gp3 storage, automatic backups, CloudWatch database logs, and Performance Insights** trade additional cost for availability, recovery, and operational visibility.
- **Deletion protection is on by default.** Terraform cannot destroy the RDS instance until it is explicitly disabled. A final snapshot is requested for any permitted deletion; choose a unique final-snapshot identifier if recreating after a destroy.

## Application database integration

Terraform associates the `voting-app-database` service account in the
`staging` and `production` namespaces with a dedicated Pod Identity role. That
role can describe the configured RDS instance and read only its managed master
secret. The deployment script supplies the AWS region and RDS instance
identifier to the Kubernetes ConfigMap before applying the manifests.

The init-container approach loads credentials once when a Pod starts. Restart
the worker and result Deployments after an RDS password rotation. A future
enhancement can use the Secrets Store CSI Driver with rotation reconciliation
and a verified RDS CA bundle.

## Cost and lifecycle note

This is production-oriented infrastructure and is not a free sandbox: EKS control-plane, NAT gateways, RDS Multi-AZ, EBS/RDS storage, CloudWatch, and public IPv4/EIP usage incur AWS charges. Review the plan and AWS pricing before applying. Do not run `terraform destroy` against production.
