# Golden paths

App teams get one-click composites. Infra and code stay split underneath
so a code rollback cannot rewind later infra.

Terraform owns the ECS task definition. The digest is a variable
(`image_digest`). CI never calls `aws ecs update-service` and never
reactivates `family:N`.

Directory-per-env: `envs/dev`, `envs/staging`, `envs/prod`. Separate
state keys. No Terraform workspaces.

## Create (one click, from nothing)

The factory project is this repo imported into TeamCity **once**.

1. Run **`new-api`**. Prompted: name, port, preset, optional host.
2. That job is `scripts/inception.sh`:
   - copies `services/example-api` to `services/<name>` (Dockerfile, Go,
     Terraform roots)
   - adds the name to platform `ecr_repositories` and to
     `.teamcity/services.list` (the DSL grows a subproject on reload)
   - builds the first image (`<name>:inception`)
   - commits so versioned settings can see the new pipelines
   - if AWS creds are a real account (not `784318225077`), runs
     `infra / apply` as the first deploy
3. After TeamCity reloads settings, the app already has `create`,
   `ship`, `promote`, `rollback`. If AWS was skipped, run
   **`<name> / create (dev)`** once against a real account.

Shared VPC, cluster, and ALB are **not** created per app. Platform is
applied as part of first create, not as a second product.

Same thing on a laptop: `make inception NAME=orders-api`.

## Ship (one click, day-2)

Move a **code** change as far as dev.

1. PR. `code / plan (dev)` builds, then `terraform plan` with the new
   digest. The plan must only change `aws_ecs_task_definition` /
   `aws_ecs_service`. Anything else fails: that belongs on infra.
2. Merge to `main`. **`ship (dev)`** runs `code / build` then
   `code / deploy (dev)`. Infra apply is not on this button.
3. Circuit breaker plus rollback is in the module. A bad `/health` rolls
   back that deploy without a CI script.

Do not retag `latest`. Do not call ECS APIs from the build.

## Promote (one click per env)

Same image digest, next environment. No rebuild.

1. **`promote (staging)`** snapshots `ship (dev)` and runs
   `code / deploy (staging)` with the same `IMAGE_DIGEST`.
2. **`promote (prod)`** snapshots staging, waits for `prod-approvers`
   on the deploy, then `code / deploy (prod)`.

If staging is bad, do not promote. Ship a new image, or use Rollback.

## Rollback

Two different buttons. Mixing them is how you get drift.

**Code is broken, infra is fine.** Run `code / rollback ($env)`. Type
the last good digest from `code / build` history. The build checks out
**current** `main`, plans with that digest, and applies only if the plan
is the image. New task-def revision = today's CPU, secrets, IAM, plus
the old image.

**Infra is broken.** Revert the Terraform on a PR. `infra / plan` then
`infra / apply ($env)` reads the digest currently in state and passes it
through, so the image does not rewind. Prod still needs approval.

A failed deploy in the last few minutes can use the ECS circuit breaker
(previous revision of *that* deploy). That is not how you undo last
Tuesday.

Never:

- TeamCity "Re-run" of an old apply (old checkout = old infra snapshot)
- `aws ecs update-service --task-definition family:37`
- `git checkout` an old SHA and apply it to roll back code

## Infra (not an app-team button)

`infra / apply ($env)` applies `platform/envs/$env` then
`services/<name>/envs/$env`. If the service already exists it **preserves**
`image_digest` from state. App teams do not run this unless they changed
Terraform (CPU preset, secrets ARNs, count, listener). Path filters on
`modules/**`, `platform/**`, `services/*/envs/**` trigger it.

## Why the digest is the handoff

Mutable tags (`:latest`, `:main`) make staging and prod unverifiable.
The task definition pins `@sha256:…`. Promote and code rollback are then
a Terraform variable change in a different state key, not a new image
and not an old revision.

ECR lives once per account (`manage_ecr = true` in a single platform
env) so every env can pull that digest.
