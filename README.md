# Example Voting App

A simple distributed application running across multiple Docker containers.

## Getting started

Download [Docker Desktop](https://www.docker.com/products/docker-desktop) for Mac or Windows. [Docker Compose](https://docs.docker.com/compose) will be automatically installed. On Linux, make sure you have the latest version of [Compose](https://docs.docker.com/compose/install/).

This solution uses Python, Node.js, .NET, with Redis for messaging and Postgres for storage.

Run in this directory to build and run the app:

```shell
docker compose up
```

The `vote` app will be running at [http://localhost:8080](http://localhost:8080), and the `results` will be at [http://localhost:8081](http://localhost:8081).

Alternately, if you want to run it on a [Docker Swarm](https://docs.docker.com/engine/swarm/), first make sure you have a swarm. If you don't, run:

```shell
docker swarm init
```

Once you have your swarm, in this directory run:

```shell
docker stack deploy --compose-file docker-stack.yml vote
```

## Run the app in Kubernetes

The folder k8s-specifications contains the YAML specifications of the Voting App's services.

Run the following command to create the deployments and services. Note it will create these resources in your current namespace (`default` if you haven't changed it.)

```shell
kubectl create -f k8s-specifications/
```

The `vote` web app is then available on port 31000 on each host of the cluster, the `result` web app is available on port 31001.

To remove them, run:

```shell
kubectl delete -f k8s-specifications/
```

## Architecture

![Architecture diagram](architecture.excalidraw.png)

* A front-end web app in [Python](/vote) which lets you vote between two options
* A [Redis](https://hub.docker.com/_/redis/) which collects new votes
* A [.NET](/worker/) worker which consumes votes and stores them in…
* A [Postgres](https://hub.docker.com/_/postgres/) database backed by a Docker volume
* A [Node.js](/result) web app which shows the results of the voting in real time

## CI/CD

The GitHub Actions workflow in `.github/workflows/ci-cd.yml` runs the Python,
Node.js, and .NET test suites, validates Terraform and Kubernetes configuration,
and builds all three application images on every pull request and push. For a
deployment, it then calls `.github/workflows/terraform-apply.yml`; application
images are published and deployed only after that infrastructure apply succeeds.

Deployment behavior is intentionally branch and environment based:

| Trigger | GitHub environment | Kubernetes namespace | Deployment |
| --- | --- | --- | --- |
| Push to `develop` | `staging` | environment variable or `staging` | Automatic after CI |
| Push to `main` | `production` | environment variable or `production` | After production environment approval |
| Manual dispatch | Selected environment | environment variable or selection | After CI and environment rules |

Staging uses NodePorts `32000`/`32001`; production retains `31000`/`31001`,
avoiding cluster-wide NodePort collisions when both namespaces are deployed.

Images are pushed to the three ECR repositories with the immutable Git commit
SHA as the tag. The deployment script renders the Kubernetes manifests with
those exact images, applies the staging or production replica overlay, and waits
for every Deployment rollout.

Create `staging` and `production` environments under **GitHub repository
Settings > Environments**. Add these environment variables to both:

- `AWS_ROLE_ARN`: the `github_actions_role_arn` bootstrap output;
- `AWS_REGION`: for example `ap-south-1`;
- `EKS_CLUSTER_NAME`: normally `voting-app-production`;
- `ECR_REPOSITORY_PREFIX`: normally `voting-app`;
- `KUBERNETES_NAMESPACE`: `staging` or `production`.

Configure required reviewers on the `production` environment. The deployment
job uses GitHub OIDC, so it does not need AWS access-key secrets.

Create a repository Actions secret named `TF_API_TOKEN` containing an HCP
Terraform user or team token that can plan and apply the `Voting_app_CLI`
workspace. This token authenticates the Terraform CLI to HCP Terraform; AWS
access inside the remote run still uses the short-lived HCP OIDC role.

The infrastructure workflow runs this sequence:

```text
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

The `terraform-oidc-bootstrap` configuration remains a one-time local apply.
It cannot be part of the remote pipeline because it creates the HCP Terraform
role used by that pipeline.

The application deployment runs on a GitHub-hosted Ubuntu runner. The EKS public
API endpoint must therefore accept connections from that runner. GitHub-hosted
runner addresses are not stable enough for a small static allowlist, so this
setup currently relies on the configured public-access CIDRs. AWS IAM and EKS
access policies still authenticate and authorize the deployment role.

Before the first deployment, apply `terraform-oidc-bootstrap`, set its
`github_actions_role_arn` output as the HCP Terraform variable
`github_actions_role_arn`, and apply the main `terraform` configuration. This
creates the EKS access entry used by the deployment role.

## Notes

The voting application only accepts one vote per client browser. It does not register additional votes if a vote has already been submitted from a client.

This isn't an example of a properly architected perfectly designed distributed app... it's just a simple
example of the various types of pieces and languages you might see (queues, persistent data, etc), and how to
deal with them in Docker at a basic level.
