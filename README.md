# ECS Fargate HTTP API — golden path factory

Platform **factory** you can hand to an app team. Fake AWS account
`784318225077`, region `eu-west-1`. It will not apply against a real
account without you changing IDs, backends, and DNS.

Two repos:

| Repo | Owns |
| --- | --- |
| **This factory** | Shared modules, shared platform (VPC, NAT, cluster, ECR), the app template, `new-api` |
| **Each app repo** (created by `new-api`) | Go app + Dockerfile at repo root, thin Terraform roots, TeamCity Kotlin for that service only |

CI is **TeamCity**. Infra is **Terraform**. Import this factory once.
Click `new-api` to create a private GitHub app repo and a TeamCity
project whose versioned settings VCS root **is that app**. Then run
**create (dev)** on the app project. Day-2 `ship` only moves a digest.
Terraform owns the task definition. CI does not call
`aws ecs update-service`.

**One ALB per app.** Internal vs internet-facing is an app tfvars
choice (`alb_internal`). Shared host-header routing on a platform ALB
is not the product path. Fargate tasks stay in private subnets with no
public IP.

## Layout (factory)

```
modules/ecs-api/                 # golden service module (task + dedicated ALB)
modules/platform/                # stub: VPC, NAT, cluster, ECR
platform/envs/{dev,staging,prod} # thin platform roots, own state keys
templates/service-api/           # TEMPLATE copied into a new app repo
.teamcity/settings.kts           # factory: new-api, local-checks, platform apply
scripts/inception.sh             # new-api implementation
```

The generated **app repo** looks like:

```
Dockerfile  main.go  go.mod      # repo root, not services/<name>
envs/{dev,staging,prod}          # git:: factory //modules/ecs-api?ref=main
.teamcity/settings.kts           # THIS service: build, create, ship, promote, rollback
scripts/                         # plan/apply helpers the pipelines call
```

Module source in app env roots (pin `ref=` to a tag in production):

```
git::https://github.com/Funkythumbs42/ecs-fargate-api-golden-path.git//modules/ecs-api?ref=main
```

State is directory-per-env, not workspaces. Each env directory has
`backend.hcl.example` pointing at a distinct key. App roots still use
`terraform_remote_state` for the platform stack.

## Golden paths

See [GOLDEN_PATHS.md](GOLDEN_PATHS.md) for the operator detail.

| Path | What happens |
| --- | --- |
| **Create** | Factory `new-api` → GitHub app repo + TeamCity project. Then app **`create (dev)`** builds, applies this app's Terraform (dedicated ALB + service). |
| **Ship** | App `ship (dev)`: build + code deploy. Infra is not on this button. |
| **Promote** | Same digest to staging then prod. Prod has an approval. No rebuild. |
| **Rollback** | App `rollback ($env)`: current Terraform + a previous digest. Never an old task-def revision. |

## Module contract (`modules/ecs-api`)

Required inputs: `service_name`, `environment`, `image_digest`,
`cpu_mem_preset` (`small` | `medium` | `large`), `container_port`,
`secrets` (map of env var name → SSM Parameter Store or Secrets Manager
**ARN**).

ALB: `alb_internal` (`false` = internet-facing in public subnets,
`true` = internal in private subnets). Default listener forwards `/*`
to this service. Output `alb_dns_name` is what you curl — no fake Host
header.

Optional: `desired_count`, `health_check_path` (default `/health`),
`tags`, `enable_execute_command`.

Baked in:

- Fargate + `awsvpc` in **private** subnets, `assign_public_ip = false`
- Dedicated ALB + listener + target group + ALB SG
- CloudWatch Logs
- Task SG admits **this app's** ALB SG on `container_port` only
- Deployment circuit breaker with rollback
- CPU and ALB-request-count target tracking
- ECS Exec off unless the env root sets the variable (prod tfvars: `false`)

Secrets are container `secrets` from ARNs. A plaintext value in tfvars
fails validation.

Platform wiring (cluster, VPC, public + private subnets, ECR URL) comes
from `terraform_remote_state` of the platform stack. The service root
does not create those. It **does** create the ALB.

Outputs: `service_name`, `task_definition_arn`, `target_group_arn`,
`log_group`, `security_group_id`, `alb_dns_name`, `alb_arn`,
`image_digest`.

## Platform vs app

| | Platform (`modules/platform`) | App (`modules/ecs-api` in the app repo) |
| --- | --- | --- |
| Who | Platform team | App team |
| State | `platform/<env>/terraform.tfstate` | `services/<name>/<env>/terraform.tfstate` |
| Contains | VPC, NAT, cluster, ECR, leftover PoC ALB | Dedicated ALB, task def, service, SGs, logs, autoscaling |
| Apply cadence | Rare (factory `platform apply`) | Every Ship / Promote / first create |

This platform stub is an **example**, not a landing zone. One NAT,
HTTP only, no VPC endpoints, no TLS. Prod on the internet should add
ACM on 443 before you copy it.

The shared ALB still in `modules/platform` is leftover for the live PoC
stack. Do not delete it from AWS. New apps ignore those outputs.

ECR is account-global so Promote can pull the same digest: `manage_ecr = true` in **one** env (dev here); staging/prod look the repo up.
`new-api` appends the service name to `ecr_repositories`; run factory
`platform apply (dev)` if the repo does not exist yet.

Remote state bootstrap is a chicken-and-egg: create the bucket and
lock table out of band, or set `create_state_backend = true` on a
local apply once, then migrate. `backend.hcl.example` is the shape.

## TeamCity

Factory `.teamcity/settings.kts` is Kotlin DSL
(`jetbrains.buildServer.configs.kotlin.*`), `version = "2024.12"`.

| Build (factory) | Role |
| --- | --- |
| **`new-api`** | Create GitHub app repo + register its TeamCity project. Prompted name/port/preset/ALB/git. |
| `local-checks` | Offline: docker build of the template + terraform fmt/validate. |
| `platform apply ($env)` | Shared VPC/cluster/ECR only. |

Each **app** project (Kotlin in that repo) has `create (dev)`,
`ship (dev)`, `promote`, `infra apply`, `code deploy`, `rollback`.
Those pipelines check out the **app** repo.

AWS is an assumed role / OIDC connection (`%aws.role.arn%`). There are
no long-lived keys in the DSL.

New service: Run factory `new-api`. Do not copy the DSL by hand. Do not
copy app files into `services/` on the factory.

To click through the factory DSL on a laptop, see
[LOCAL_TEAMCITY.md](LOCAL_TEAMCITY.md). Apply to ECS Fargate still needs
real AWS; LocalStack is not part of this example.

## Try locally

Needs Docker. No AWS required.

```bash
make docker-build          # example-api:local from templates/service-api
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
make tf-validate           # init -backend=false in each factory root; downloads the AWS provider
```

`terraform plan` / `apply` need real credentials, a backend, and the
placeholder account replaced. Do not apply this example as-is.

Go compile check:

```bash
cd templates/service-api && go build -o /tmp/example-api .
```

## Constraints worth not violating

- Region is `eu-west-1`. Account ID in this repo is an example sandbox.
- Image reference in the task def is `repo@sha256:…`, never a moving tag.
- Directory-per-env, one state key each.
- One ALB per app; `alb_internal` is the scheme knob.
- No GitHub Actions.
- No secrets in git. `secrets = {}` in the example tfvars; fill with ARNs.
