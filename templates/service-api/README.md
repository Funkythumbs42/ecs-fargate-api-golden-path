# example-api

Standalone HTTP API created from the ECS Fargate factory
(`Funkythumbs42/ecs-fargate-api-golden-path`).

This repo owns the Go app, the service Terraform, and the TeamCity
Kotlin DSL. Shared VPC / NAT / cluster / ECR live in the factory.
**This app has its own ALB** (not a host rule on a shared balancer).

## Layout

```
Dockerfile                 # image build context is the repo root
main.go
envs/{dev,staging,prod}    # thin Terraform roots
.teamcity/                 # pipelines for THIS service only
scripts/                   # plan/apply helpers the pipelines call
```

Terraform pulls the golden module with a git source:

```
git::https://github.com/Funkythumbs42/ecs-fargate-api-golden-path.git//modules/ecs-api?ref=main
```

Pin `ref=` to a tag or commit in production. `terraform init` needs
read access to that private factory repo (agent GitHub credentials).

`alb_internal` in each env's `terraform.tfvars` chooses the ALB:

| Value | Scheme | Subnets |
| --- | --- | --- |
| `false` (default) | internet-facing | platform public subnets |
| `true` | internal | platform private subnets |

Fargate tasks stay in private subnets with no public IP either way.
The default listener forwards `/*` to this service. After `create (dev)`
or `ship (dev)`, curl the `alb_dns_name` output — no fake Host header.

```bash
curl -s http://$(terraform -chdir=envs/dev output -raw alb_dns_name)/health
```

## Pipelines (this repo's TeamCity project)

TeamCity versioned settings VCS root **is this repo**. Builds check out
this repo, not the factory.

| Build | Role |
| --- | --- |
| **create (dev)** | First AWS deploy: build + infra apply (ALB + service) |
| **ship (dev)** | Day-2: build + code deploy (digest only) |
| **promote (staging/prod)** | Same digest, next env |
| **rollback ($env)** | Current Terraform + a previous digest |
| infra / code plan+apply | Split so a code rollback cannot rewind later infra |

## Local

```bash
make docker-build
make docker-run
curl -s localhost:8080/health
```
