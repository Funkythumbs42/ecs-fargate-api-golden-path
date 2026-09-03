# ecs-api

Golden Terraform module for an HTTP API on ECS Fargate.

App teams do not write task definitions, listener rules, or autoscaling
from scratch. They call this module from a thin env root and pass
`image_digest` from CI.

## Contract

Required:

| Input | Meaning |
| --- | --- |
| `service_name` | DNS-safe name |
| `image_digest` | `sha256:…` from the image CI just pushed |
| `cpu_mem_preset` | `small` \| `medium` \| `large` |
| `container_port` | Container listen port |
| `secrets` | map of env name → SSM / Secrets Manager **ARN** |

Platform wiring (from `terraform_remote_state` of the platform stack):
cluster name, VPC, private subnet IDs, ALB listener ARN, ALB SG, ALB
ARN suffix, ECR repository URL. `assign_public_ip` stays `false`.

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
`security_group_id`, `image`.
