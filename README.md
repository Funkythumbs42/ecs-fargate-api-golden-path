# ECS Fargate HTTP API — golden path example

Platform example you can hand to an app team. Fake AWS account
`784318225077`, region `eu-west-1`. It will not apply against a real
account without you changing IDs, backends, and DNS.

CI is **TeamCity**. Infra is **Terraform**. Import this repo once as
the **factory**. Click `new-api` to create an application from nothing
(files, image, pipelines, first deploy). Day-2 `ship` only moves a
digest. Terraform owns the task definition. CI does not call
`aws ecs update-service`.

## Layout

```
modules/ecs-api/                 # golden service module
modules/platform/                # stub: VPC, cluster, ALB, ECR
platform/envs/{dev,staging,prod} # thin platform roots, own state keys
services/example-api/            # one example service (Go + Docker)
services/example-api/envs/*      # thin service roots (~60 lines)
.teamcity/settings.kts           # build → plan → apply → promote
```

State is directory-per-env, not workspaces. Each env directory has
`backend.hcl.example` pointing at a distinct key.

## Golden paths

See [GOLDEN_PATHS.md](GOLDEN_PATHS.md) for the operator detail.

| Path | What happens |
| --- | --- |
| **Create** | Run `new-api` (or `make inception NAME=...`). Scaffolds Terraform/Docker/Go, registers pipelines, builds the first image, first-deploys if AWS is real. |
| **Ship** | `ship (dev)`: build + code deploy. Infra is not on this button. |
| **Promote** | Same digest to staging then prod. Prod has an approval. No rebuild. |
| **Rollback** | `rollback ($env)`: current Terraform + a previous digest. Never an old task-def revision. |

## Module contract (`modules/ecs-api`)

Required inputs: `service_name`, `image_digest`, `cpu_mem_preset`
(`small` | `medium` | `large`), `container_port`, `secrets` (map of
env var name → SSM Parameter Store or Secrets Manager **ARN**).

Optional: `desired_count`, `health_check_path` (default `/health`),
`host_header` (ALB host rule; if omitted, path pattern `/*`), `tags`,
`enable_execute_command`.

Baked in:

- Fargate + `awsvpc` in **private** subnets, `assign_public_ip = false`
- ALB listener rule (host or path)
- CloudWatch Logs
- Task SG admits the ALB SG on `container_port` only
- Deployment circuit breaker with rollback
- CPU and ALB-request-count target tracking
- ECS Exec off unless the env root sets the variable (prod tfvars: `false`)

Secrets are container `secrets` from ARNs. A plaintext value in tfvars
fails validation.

Platform wiring (cluster, VPC, private subnets, ALB listener/SG/ARN
suffix, ECR URL) comes from `terraform_remote_state` of the platform
stack. The service root does not create those.

Outputs: `service_name`, `task_definition_arn`, `target_group_arn`,
`log_group`, `security_group_id`.

## Platform vs service

| | Platform (`modules/platform`) | Service (`modules/ecs-api`) |
| --- | --- | --- |
| Who | Platform team | App team |
| State | `platform/<env>/terraform.tfstate` | `services/<name>/<env>/terraform.tfstate` |
| Contains | VPC, cluster, ALB (HTTP/80, default 404), ECR, optional state bucket | Task def, service, SG, listener rule, logs, autoscaling |
| Apply cadence | Rare | Every Ship / Promote |

This platform stub is an **example**, not a landing zone. One NAT,
HTTP only, no VPC endpoints, no TLS. Prod on the internet should add
ACM on 443 before you copy it.

ECR is account-global so Promote can pull the same digest: `manage_ecr = true` in **one** env (dev here); staging/prod look the repo up.

Remote state bootstrap is a chicken-and-egg: create the bucket and
lock table out of band, or set `create_state_backend = true` on a
local apply once, then migrate. `backend.hcl.example` is the shape.

## TeamCity

`.teamcity/settings.kts` is Kotlin DSL (`jetbrains.buildServer.configs.kotlin.*`).

| Build | Role |
| --- | --- |
| **`new-api`** | Factory. From inception: scaffold + image + register pipelines. Prompted name/port/preset. |
| `local-checks` | Offline: docker build + terraform fmt/validate. |
| Per service after that | `create (dev)`, `ship (dev)`, `promote`, `infra apply`, `code deploy`, `rollback` |

AWS is an assumed role / OIDC connection (`%aws.role.arn%`). There are
no long-lived keys in the DSL.

New service: Run `new-api`. Do not copy the DSL by hand.

To click through the DSL on a laptop, see [LOCAL_TEAMCITY.md](LOCAL_TEAMCITY.md).
Apply to ECS Fargate still needs real AWS; LocalStack is not part of this example.

## Try locally

Needs Docker. No AWS required.

```bash
make docker-build          # example-api:local
make docker-run            # publishes :8080
curl -s localhost:8080/health
curl -s localhost:8080/
```

Expect `{"status":"ok"}` and `{"service":"example-api","version":"local"}`.

Local TeamCity in containers (UI on `:8111`, first start ~4GB RAM):

```bash
make teamcity-up           # see LOCAL_TEAMCITY.md
```

Terraform formatting / syntax (still no account required for `fmt`):

```bash
make tf-fmt
make tf-validate           # init -backend=false in each root; downloads the AWS provider
```

`terraform plan` / `apply` need real credentials, a backend, and the
placeholder account replaced. Do not apply this example as-is.

Go compile check:

```bash
cd services/example-api && go build -o /tmp/example-api .
```

## Constraints worth not violating

- Region is `eu-west-1`. Account ID in this repo is fake.
- Image reference in the task def is `repo@sha256:…`, never a moving tag.
- Directory-per-env, one state key each.
- No GitHub Actions.
- No secrets in git. `secrets = {}` in the example tfvars; fill with ARNs.
