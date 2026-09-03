# ecs-api

Golden Terraform module for an HTTP API on ECS Fargate.

App teams do not write task definitions, load balancers, or autoscaling
from scratch. They call this module from a thin env root in **their**
app repo and pass `image_digest` from CI.

## Contract

Required:

| Input | Meaning |
| --- | --- |
| `service_name` | DNS-safe name |
| `environment` | `dev` / `staging` / `prod` (ALB and log names) |
| `image_digest` | `sha256:…` from the image CI just pushed |
| `cpu_mem_preset` | `small` \| `medium` \| `large` |
| `container_port` | Container listen port |
| `secrets` | map of env name → SSM / Secrets Manager **ARN** |

This module **owns the ALB** for the app (listener, target group, ALB
security group). `alb_internal = false` (default) places an
internet-facing ALB in public subnets. `alb_internal = true` places an
internal ALB in private subnets. The default listener forwards `/*` to
this service — no shared Host-header routing.

Platform wiring (from `terraform_remote_state` of the platform stack):
cluster name, VPC, private subnet IDs, public subnet IDs, ECR repository
URL. `assign_public_ip` stays `false`. Fargate tasks always run in
private subnets.

This module **owns the task definition**. CI never calls
`aws ecs update-service` / `register-task-definition`.

Secrets are injected as container `secrets` from ARNs. Putting a
plaintext secret in tfvars is rejected by validation.

ECS Exec is a variable. Prod tfvars keep it `false`.

## Presets

| Preset | CPU | Memory |
| --- | --- | --- |
| small | 256 | 512 |
| medium | 512 | 1024 |
| large | 1024 | 2048 |

## Outputs

`service_name`, `task_definition_arn`, `target_group_arn`, `log_group`,
`security_group_id`, `image`, `image_digest`, `alb_dns_name`, `alb_arn`.
