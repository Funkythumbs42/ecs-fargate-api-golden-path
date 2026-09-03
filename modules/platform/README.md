# platform (stub)

Example shared platform: VPC, ECS cluster, public ALB (HTTP/80, default 404),
ECR repos, optional state bucket + lock table.

This is **not** a landing zone. No TLS, no VPC endpoints, one NAT, fake
account `123456789012`, region `eu-west-1`.

Service modules consume the outputs listed in `outputs.tf`. They do not
create clusters, ALBs, or ECR repos.
