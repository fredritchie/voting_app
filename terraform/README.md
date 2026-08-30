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

- **RDS PostgreSQL replaces the in-cluster `db` deployment.** Application manifests must use the `rds_endpoint` output and retrieve its credentials from Secrets Manager rather than connect to hostname `db` with `postgres/postgres`.
- **Multi-AZ, encrypted gp3 storage, automatic backups, CloudWatch database logs, and Performance Insights** trade additional cost for availability, recovery, and operational visibility.
- **Deletion protection is on by default.** Terraform cannot destroy the RDS instance until it is explicitly disabled. A final snapshot is requested for any permitted deletion; choose a unique final-snapshot identifier if recreating after a destroy.

## Not included yet

This layer intentionally does not deploy Kubernetes workloads. The existing Kubernetes manifests still point at local/sample components and must next be changed to:

1. remove the in-cluster PostgreSQL deployment and service;
2. give the worker and result services an RDS connection/secret configuration;
3. publish images to the ECR repositories and replace the Docker Hub image references;
4. add an AWS Load Balancer Controller/Ingress or other chosen external entry point;
5. use External Secrets, the Secrets Store CSI driver, or a comparable mechanism to expose the RDS-managed secret to the Pods with least-privilege workload identity.

## Cost and lifecycle note

This is production-oriented infrastructure and is not a free sandbox: EKS control-plane, NAT gateways, RDS Multi-AZ, EBS/RDS storage, CloudWatch, and public IPv4/EIP usage incur AWS charges. Review the plan and AWS pricing before applying. Do not run `terraform destroy` against production.
