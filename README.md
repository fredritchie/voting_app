# Voting Application on AWS

This repository deploys a distributed voting application to Amazon EKS. AWS
infrastructure is managed with Terraform and HCP Terraform, application delivery
is automated with GitHub Actions, container images are stored in Amazon ECR,
PostgreSQL runs on Amazon RDS, and logs and metrics are centralized in Amazon
CloudWatch.

## Application flow

```text
Browser
  -> vote (Python)
  -> Redis queue
  -> worker (.NET)
  -> Amazon RDS for PostgreSQL
  -> result (Node.js and WebSocket)
  -> Browser
```

- `vote` receives a vote and sends it to Redis.
- `worker` consumes the vote, creates the `votes` table when necessary, and
  writes the vote to PostgreSQL.
- `result` reads aggregate results from PostgreSQL and streams updates to the
  browser.

For a detailed visual, open
[`docs/voting-app-aws-architecture.drawio`](docs/voting-app-aws-architecture.drawio)
in draw.io.

## Repository structure

| Path | Purpose |
| --- | --- |
| `vote/` | Python voting frontend and tests |
| `result/` | Node.js results frontend and tests |
| `worker/` | .NET queue worker and tests |
| `k8s-specifications/` | Base Kubernetes resources |
| `k8s-overlays/staging/` | One-replica staging overlay with no public load balancer |
| `k8s-overlays/production/` | Three-replica production overlay with public load balancers |
| `terraform/` | Main AWS infrastructure managed through HCP Terraform |
| `terraform-oidc-bootstrap/` | One-time AWS IAM and OIDC bootstrap configuration |
| `.github/workflows/` | CI/CD and HCP Terraform workflows |
| `scripts/deploy.sh` | Immutable-image Kubernetes deployment script |
| `docs/` | Architecture and troubleshooting documentation |

## Cloud architecture

The main Terraform configuration creates:

- a VPC with public, private, and isolated database subnets;
- public Internet Gateway routing;
- one NAT Gateway and Elastic IP per Availability Zone;
- an EKS cluster with a private managed node group;
- private ECR repositories for `vote`, `result`, and `worker`;
- a private, encrypted, Multi-AZ RDS PostgreSQL instance;
- IAM roles, EKS access entries, and EKS Pod Identity associations;
- Container Insights, centralized CloudWatch log groups, and two dashboards.

The current checked-in variables use two Availability Zones and three
`t3.medium` EKS nodes. Terraform supports two or three Availability Zones and
allows the node group to scale between its configured minimum and maximum.

### Network path

```text
Internet
  -> public AWS load balancer
  -> worker-node NodePort
  -> Kubernetes Service
  -> application Pod in a private subnet

Application Pod
  -> RDS security group on TCP/5432
  -> private RDS PostgreSQL in isolated database subnets
```

EKS worker nodes do not receive public IP addresses. They use same-AZ NAT
Gateways for outbound access such as pulling images. RDS is not publicly
accessible and has no internet default route.

## Architectural decisions

### HCP Terraform for state and execution

The `terraform` directory uses the Terraform `cloud` block. HCP Terraform
provides remote state, locking, run history, cost estimation, and centralized
workspace variables. This avoids local-state conflicts and prevents concurrent
applies against the same infrastructure.

The OIDC bootstrap remains separate because the HCP Terraform execution role
cannot create itself. It is applied once with an existing AWS administrator
identity and reapplied when the bootstrap permissions change.

### EKS managed node group

EKS manages worker-node registration, replacement, and rolling updates. Three
nodes provide a baseline that allows workloads to remain available during a
single-node update or failure.

Staging and production currently share the cluster but use separate Kubernetes
namespaces. This reduces cost, while separate clusters would provide stronger
security and failure isolation.

### Environment-specific exposure

- Staging runs one replica of each application component and has no public load
  balancer. It is intended for authenticated internal testing or port-forwarding.
- Production runs three replicas and changes the `vote` and `result` Services to
  `LoadBalancer` on port 80.

The load balancers register EKS worker nodes. Traffic is forwarded through
NodePorts `31000` and `31001`, and Kubernetes routes it to matching Pods.

### Immutable ECR images

Application images are built from the repository Dockerfiles and tagged with
the Git commit SHA. ECR tag immutability prevents an existing release from being
overwritten and makes every deployment traceable to source code.

If all three images for a commit already exist, the release job skips rebuilding
them and deploys the existing immutable images. GitHub Actions cache may reuse
unchanged Docker layers.

### Managed PostgreSQL

RDS replaces the sample in-cluster PostgreSQL Deployment. It provides encrypted
gp3 storage, Multi-AZ failover, automated backups, PostgreSQL logs, Performance
Insights, and an AWS-managed master password.

The `worker` and `result` Pods use the `voting-app-database` service account. EKS
Pod Identity grants that service account a narrowly scoped IAM role. An AWS CLI
init container:

1. discovers the private endpoint and port from RDS;
2. reads the RDS-managed username and password from Secrets Manager;
3. writes both files to a memory-backed `emptyDir` volume;
4. exits before the application container starts.

Credentials are not committed, passed through GitHub Actions, or stored in a
Kubernetes Secret object. The applications connect to database `voting` over an
encrypted PostgreSQL connection.

### Centralized observability

The Amazon CloudWatch Observability EKS add-on supplies the CloudWatch agent and
Fluent Bit. It uses a dedicated Pod Identity role and publishes application,
data-plane, host, and performance telemetry.

Terraform creates:

- an infrastructure dashboard for EKS nodes, CPU, memory, RDS, NAT traffic, and
  control-plane errors;
- an application dashboard for Pod counts, CPU, memory, restarts, vote events,
  errors, and recent logs.

## Prerequisites

- An AWS account and an administrator identity for the initial bootstrap
- An HCP Terraform organization, project, and workspace
- A GitHub repository with permission to configure Actions environments
- Terraform `1.16.0`
- AWS CLI v2
- `kubectl`
- Docker for local development and optional local image checks

Confirm the AWS account before bootstrapping:

```bash
aws sts get-caller-identity
```

## Local development

The Docker Compose configuration retains the original local PostgreSQL
container and does not use cloud RDS:

```bash
docker compose up --build
```

Open:

- Vote: <http://localhost:8080>
- Results: <http://localhost:8081>

## Initial cloud setup

### 1. Create the HCP Terraform workspace

Create or select:

- Organization: `ritchie-corp`
- Project: `voting_app_infra`
- Workspace: `Voting_app_CLI`
- Working directory: `terraform`
- Terraform version: `1.16.0`

If these names differ, update `terraform/versions.tf` and the bootstrap input
values so the OIDC trust claims match exactly.

### 2. Bootstrap AWS IAM and OIDC

The bootstrap creates the HCP Terraform OIDC provider and execution role. It
also reads the account's existing GitHub Actions OIDC provider and creates the
GitHub deployment role.

```bash
cd terraform-oidc-bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Set the HCP organization, project, workspace, GitHub repository, and role-name
values, then run:

```bash
terraform init
terraform plan
terraform apply
```

Do not commit `terraform.tfvars`, Terraform state, saved plan files, or AWS
credentials.

If an HCP OIDC provider already exists in the account, import it instead of
creating a duplicate. See
[`terraform-oidc-bootstrap/README.md`](terraform-oidc-bootstrap/README.md).

### 3. Configure dynamic AWS credentials in HCP Terraform

Run:

```bash
terraform output hcp_terraform_workspace_environment_variables
```

Add the returned values to the HCP workspace as **Environment variables**:

```text
TFC_AWS_PROVIDER_AUTH=true
TFC_AWS_RUN_ROLE_ARN=<HCP Terraform role ARN>
```

These enable short-lived AWS credentials through OIDC. Do not configure
`AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in the workspace.

Add these HCP workspace **Terraform variables**:

| Variable | Example | Notes |
| --- | --- | --- |
| `aws_region` | `ap-south-1` | Region for all resources |
| `eks_public_access_cidrs` | `["203.0.113.10/32"]` | HCL list of trusted Kubernetes API CIDRs |
| `github_actions_role_arn` | Bootstrap output | Creates the GitHub EKS access entry |
| `eks_application_admin_principal_arns` | `["arn:aws:iam::ACCOUNT:user/operator"]` | Optional namespace administrators |

Workspace variables should override repository examples for each real
environment. Mark only actual secrets as sensitive.

### 4. Configure GitHub Actions

Create `staging` and `production` environments under **Settings > Environments**.
Require reviewers for the production environment.

Add these variables to both environments:

| Variable | Typical value |
| --- | --- |
| `AWS_ROLE_ARN` | `github_actions_role_arn` bootstrap output |
| `AWS_REGION` | `ap-south-1` |
| `EKS_CLUSTER_NAME` | `voting-app-production` |
| `ECR_REPOSITORY_PREFIX` | `voting-app` |
| `KUBERNETES_NAMESPACE` | `staging` or `production` |
| `RDS_INSTANCE_IDENTIFIER` | `voting-app-production-postgres` |

Add the repository Actions secret:

```text
TF_API_TOKEN=<HCP Terraform user or team token>
```

`TF_API_TOKEN` authenticates the Terraform CLI to HCP Terraform. AWS access
inside the remote run still uses HCP OIDC.

### 5. Apply the main infrastructure

Either run the infrastructure workflow or use the CLI with remote execution:

```bash
cd terraform
terraform login
terraform init
terraform plan
terraform apply
```

The bootstrap must be applied before the main configuration because HCP
Terraform needs permission to create the application Pod Identity role and its
inline policy.

## CI/CD behavior

The main workflow is `.github/workflows/ci-cd.yml`.

Every pull request and push runs:

- Python, Node.js, and .NET tests;
- Terraform formatting and validation;
- staging and production Kustomize rendering;
- Docker builds without publishing.

Deployments follow this sequence:

```text
Tests and validation
  -> HCP Terraform plan/apply
  -> AWS OIDC authentication
  -> build missing commit-SHA images
  -> push to ECR
  -> configure EKS access
  -> apply Kustomize overlay
  -> wait for rollouts
```

| Trigger | Environment | Namespace | Behavior |
| --- | --- | --- | --- |
| Pull request | None | None | Validate and build only |
| Push to `develop` | Staging | `staging` | Automatic deployment |
| Push to `main` | Production | `production` | Deployment after environment approval |
| Manual dispatch | Selected | Selected | Uses selected environment rules |

Terraform apply is skipped when the remote plan reports no infrastructure
changes.

## Verification and access

Configure local Kubernetes access:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name voting-app-production

kubectl get pods --all-namespaces
```

The IAM identity running these commands needs an EKS access entry.

### Staging

Staging has no public load balancer. Use port-forwarding:

```bash
kubectl -n staging port-forward service/vote 8080:8080
kubectl -n staging port-forward service/result 8081:8081
```

### Production

Read the public AWS load-balancer hostnames:

```bash
kubectl -n production get service vote result
```

Open each value shown under `EXTERNAL-IP` or hostname on port 80.

### RDS connectivity

Check the init container and worker without printing credentials:

```bash
kubectl -n production get pods -l app=worker
kubectl -n production logs deployment/worker
kubectl -n production describe pod -l app=worker
```

The expected worker message is `Connected to db`. Never print or copy the
contents of the mounted credential file into CI logs.

### Monitoring

```bash
cd terraform
terraform output cloudwatch_dashboard_urls
terraform output container_insights_log_groups
```

Container Insights metrics may take several minutes to appear after initial
installation.

## Security considerations

### Implemented controls

| Area | Control |
| --- | --- |
| CI/CD credentials | GitHub Actions uses OIDC and short-lived AWS credentials |
| Terraform credentials | HCP Terraform uses dynamic AWS provider credentials |
| Database credentials | RDS manages the password in Secrets Manager |
| Workload access | EKS Pod Identity grants scoped secret-read permissions |
| Network isolation | EKS nodes are private and RDS is private and isolated |
| Database firewall | RDS permits TCP/5432 only from EKS private-subnet CIDRs |
| Image integrity | ECR tags are immutable and images are scanned on push |
| State protection | HCP Terraform provides remote state and locking |
| Auditability | EKS control-plane, application, host, and data-plane logs go to CloudWatch |
| Release control | Production uses GitHub Environment approval |

### Risks and production hardening

- The checked-in example currently allows `0.0.0.0/0` to reach the EKS public
  API endpoint so changing GitHub-hosted runner IPs can connect. IAM and EKS
  authorization still apply, but production should use a VPC-hosted runner,
  VPN, or another private deployment path and restrict this CIDR.
- Production load balancers currently expose HTTP. Add DNS, certificates, HTTPS
  termination, and an ALB/NLB ingress design before handling sensitive traffic.
- PostgreSQL traffic is encrypted, but the current application clients do not
  verify the RDS certificate chain. Mount the AWS RDS CA bundle and enable full
  certificate verification.
- The AWS CLI init image currently uses the mutable `latest` tag. Pin a tested
  full version or digest for deterministic production deployments.
- Credentials are loaded when a Pod starts. Restart the `worker` and `result`
  Deployments after password rotation, or adopt the Secrets Store CSI Driver
  with rotation reconciliation.
- Staging and production share an EKS cluster and RDS database. Separate AWS
  accounts, clusters, and databases provide stronger isolation.
- Redis uses `emptyDir`, so queued votes can be lost if the Redis Pod is
  rescheduled. Use a managed or persistent Redis service for production.
- Review `deletion_protection`, backup retention, and final-snapshot settings
  before treating the RDS instance as production data storage.
- Replace broad infrastructure provisioning actions with tighter permissions as
  resource names and lifecycle requirements stabilize.

## Teardown

This infrastructure creates billable EKS, EC2, NAT Gateway, load-balancer, RDS,
CloudWatch, EBS, and public IPv4 resources.

Before destroying anything:

1. verify the selected HCP workspace and AWS account;
2. export or back up required application data;
3. enable a final RDS snapshot and review deletion protection;
4. review the complete Terraform destroy plan;
5. remove Kubernetes load-balancer Services and wait for AWS load balancers to
   be deleted.

Then run the destroy through the same HCP Terraform workspace:

```bash
cd terraform
terraform plan -destroy
terraform destroy
```

Do not destroy production infrastructure solely to test the teardown process.
The OIDC bootstrap should be removed last, only after no HCP runs or GitHub
deployments require its roles.

## Troubleshooting

See [`docs/challenges-and-troubleshooting.md`](docs/challenges-and-troubleshooting.md)
for common Terraform, OIDC, IAM, Kubernetes, ECR, RDS, and CloudWatch failures.
