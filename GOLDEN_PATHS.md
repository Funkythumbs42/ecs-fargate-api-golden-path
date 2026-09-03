# Golden paths

Two repos. The **factory** (this git checkout) is imported into TeamCity
once. **`new-api`** creates a standalone **app repo** that owns the Go
app, service Terraform, and TeamCity Kotlin. Day-2 buttons live on that
app project. Pipelines check out the app repo, not the factory.

Each app gets **its own ALB**. Internal vs internet-facing is
`alb_internal` in the app's `envs/*/terraform.tfvars` (and a `new-api`
prompt). Host-header routing on a shared platform ALB is not the golden
path. Curl `alb_dns_name`; no fake Host header.

App teams get one-click composites. Infra and code stay split underneath
so a code rollback cannot rewind later infra.

Terraform owns the ECS task definition. The digest is a variable
(`image_digest`). CI never calls `aws ecs update-service` and never
reactivates `family:N`.

Directory-per-env: `envs/dev`, `envs/staging`, `envs/prod` in the app
repo. Separate state keys. No Terraform workspaces.

## Create (one click, from nothing)

1. Run factory **`new-api`**. Prompted: name, port, preset, optional DNS
   hint, **ALB scheme** (internet-facing default, or internal), **git**.
2. Git:
   - `create` (default): `gh repo create` a new **private** GitHub repo
     (optional `owner/name`; default `<you>/<service-name>`) and push the
     scaffold (app at repo root, `envs/*`, `.teamcity/`). Re-running
     `new-api` with the **same name** reuses that repo (does not create a
     second one). Empty repos get the scaffold; repos with commits are
     pointer-only.
   - `existing`: attach an existing GitHub repo (`owner/name` or URL).
     Empty repos get the scaffold; non-empty are pointer-only (not overwritten)
3. That job is `scripts/inception.sh`:
   - renders `templates/service-api` into a temp dir (replaces
     `example-api`, port, preset, `alb_internal`)
   - does **not** copy files into factory `services/`
   - adds the name to platform `ecr_repositories` and to
     `.teamcity/services.list` (a pointer registry, **not** a DSL
     subproject list)
   - builds the first image (`<name>:inception`) from the temp tree
   - `gh repo create` + push (create mode)
   - registers a TeamCity project via REST: create project, GitHub VCS
     root pointing at the **app** repo, enable Kotlin versioned settings
     (`.teamcity`). If REST cannot enable versioned settings, use the
     one-time UI click below — the Kotlin is already in the app repo.
   - commits the factory pointer + ECR name
4. If the new ECR repository is not in AWS yet, run factory
   **`platform apply (dev)`** once (shared VPC/cluster/ECR; does not
   create the app ALB).
5. After TeamCity loads the app project from the app repo, run
   **`<name> / create (dev)`**. That is the first AWS deploy: build,
   push a digest-pinned image, apply `envs/dev` (dedicated ALB +
   service). Prefer this over applying Terraform from the factory.

Same thing on a laptop: `make inception NAME=orders-api` (needs `gh`).
Then Run `create (dev)` on the new TeamCity project.

### TeamCity UI fallback (one-time)

If REST did not flip versioned settings:

1. Administration → the app project (created by `new-api`, or create it)
2. VCS Roots → Git → Fetch URL = the app GitHub repo → branch `main`
3. Versioned Settings → Synchronization enabled, format **Kotlin**,
   VCS root = that GitHub root, settings path `.teamcity`, import from VCS

## Ship (one click, day-2)

Move a **code** change as far as dev. This is an **app project** button.

1. PR in the **app** repo. `code / plan (dev)` builds, then
   `terraform plan` with the new digest. The plan must only change
   `aws_ecs_task_definition` / `aws_ecs_service`. Anything else fails:
   that belongs on infra (including ALB changes).
2. Merge to `main`. **`ship (dev)`** runs `code / build` then
   `code / deploy (dev)`. Infra apply is not on this button.
3. Circuit breaker plus rollback is in the module. A bad `/health` rolls
   back that deploy without a CI script.

Do not retag `latest`. Do not call ECS APIs from the build.

After ship, curl `http://<alb_dns_name>/health`.

## Promote (one click per env)

Same image digest, next environment. No rebuild. App project.

1. **`promote (staging)`** snapshots `ship (dev)` and runs
   `code / deploy (staging)` with the same `IMAGE_DIGEST`.
2. **`promote (prod)`** snapshots staging, waits for `prod-approvers`
   on the deploy, then `code / deploy (prod)`.

If staging is bad, do not promote. Ship a new image, or use Rollback.

## Rollback

Two different buttons. Mixing them is how you get drift.

**Code is broken, infra is fine.** Run `code / rollback ($env)` on the
app project. Type the last good digest from `code / build` history. The
build checks out **current** `main` of the **app** repo, plans with that
digest, and applies only if the plan is the image. New task-def revision
= today's CPU, secrets, IAM, ALB, plus the old image.

**Infra is broken.** Revert the Terraform on a PR in the app repo.
`infra / plan` then `infra / apply ($env)` reads the digest currently in
state and passes it through, so the image does not rewind. Prod still
needs approval.

A failed deploy in the last few minutes can use the ECS circuit breaker
(previous revision of *that* deploy). That is not how you undo last
Tuesday.

Never:

- TeamCity "Re-run" of an old apply (old checkout = old infra snapshot)
- `aws ecs update-service --task-definition family:37`
- `git checkout` an old SHA and apply it to roll back code

## Infra (not an app-team day-2 button)

**Factory** `platform apply ($env)` applies `platform/envs/$env` only
(VPC, NAT, cluster, ECR). It does not create app ALBs.

**App** `infra / apply ($env)` applies `envs/$env` in the app checkout
(dedicated ALB + service). If the service already exists it **preserves**
`image_digest` from state. App teams run this when they changed
Terraform (CPU preset, secrets ARNs, count, `alb_internal`). Path
filters on `envs/**` trigger it.

`terraform output` can print a "No outputs found" warning on stdout on a
first apply; scripts accept only a 64-hex `sha256` digest
(`scripts/tf-common.sh` in the app repo). Artifact dependencies use
`cleanDestination = false` so a digest artifact cannot wipe `scripts/`.

## Why the digest is the handoff

Mutable tags (`:latest`, `:main`) make staging and prod unverifiable.
The task definition pins `@sha256:…`. Promote and code rollback are then
a Terraform variable change in a different state key, not a new image
and not an old revision.

ECR lives once per account (`manage_ecr = true` in a single platform
env) so every env can pull that digest.

## Why one ALB per app

A shared platform ALB with host-header rules couples apps, needs a fake
Host header to curl, and is the wrong ownership line. Each app repo
applies its own ALB:

| `alb_internal` | Scheme | Subnets |
| --- | --- | --- |
| `false` (default) | internet-facing | platform public subnets |
| `true` | internal | platform private subnets |

Tasks always stay in private subnets (`assign_public_ip = false`).
The leftover shared ALB in `modules/platform` is only for the live PoC;
do not destroy it, and do not attach new apps to it.
