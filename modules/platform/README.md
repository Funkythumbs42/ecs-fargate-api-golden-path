# platform (stub)

Example shared platform: VPC, NAT, ECS cluster, ECR repos, optional
state bucket + lock table.

This is **not** a landing zone. No TLS, no VPC endpoints, one NAT, fake
account `784318225077`, region `eu-west-1`.

**Product path:** apps do **not** share an ALB. Each app repo creates
its own ALB via `modules/ecs-api` (`alb_internal` chooses
internet-facing vs internal). Platform still provides public + private
subnets so those ALBs have somewhere to land.

The ALB resources in this module are leftover for the live PoC stack.
Do not apply a deletion of them; new services simply ignore those
outputs.

Service modules consume VPC, subnet, cluster, and ECR outputs. They do
not create clusters or ECR repos.
