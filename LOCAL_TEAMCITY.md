# Local TeamCity (containers)

Run a throwaway TeamCity server + agent on your machine to click through
this repo's Kotlin DSL. This is not production CI and it is not a
substitute for AWS.

```bash
make teamcity-up     # pulls jetbrains/teamcity-* and starts :8111
make teamcity-down   # stop; named volumes keep wizard data
make teamcity-reset  # stop and delete volumes (next up is a new wizard)
```

## Budget

- First server start is slow (several minutes) and wants **~4GB RAM**.
  `TEAMCITY_SERVER_MEM_OPTS=-Xmx2g` is the heap; the JVM and page cache
  are on top.
- Images are large. Be on a decent link the first time.
- The agent bind-mounts `/var/run/docker.sock`. That is simple, and it
  means the agent is effectively **root on the host Docker daemon**.
  Use a disposable machine. The DinD alternative (`DOCKER_IN_DOCKER=start`,
  drop the socket, add `privileged: true`) is commented in
  `docker-compose.yml` if you would rather isolate the daemon.

## First-run wizard

1. `make teamcity-up` from the repo root. Wait until
   `http://localhost:8111` serves the setup pages (not a connection
   refused). `docker compose logs -f teamcity-server` if it looks stuck.
2. Create the admin user. Skip the "set up a professional license"
   nag if you are only evaluating; the OSS/evaluation flow is enough
   to load DSL.
3. Confirm the agent `local-docker-sock` is connected
   (Agents → connected). It retries until the server is up.

## Load this repo's Kotlin DSL

The server and agent both see this checkout at **the same host path**
(`HOST_REPO_PATH`, printed by `make teamcity-up` and stored in `.env`).
A Git VCS root needs a Git directory; if this tree is not a repo yet,
init one locally. This example does not create a GitHub remote.

1. Administration → **Create project** → Manually. Name it `example-api`.
2. Project Settings → **VCS Roots** → New. Type Git.
   - Fetch URL: `file://<absolute path to this repo>`
     (the `HOST_REPO_PATH` that `make teamcity-up` prints).
   - Default branch: `refs/heads/main` (or `master` if that is what
     `git init` created).
3. Project Settings → **Versioned Settings**:
   - Synchronization: enabled
   - Settings format: **Kotlin**
   - VCS root: the one you just created
   - Settings path: `.teamcity`
   - Apply changes from VCS
4. TeamCity will import `settings.kts` and create `build`, `plan`,
   `local-checks`, `apply (dev|staging|prod)`.

If versioned settings fail to parse, the Kotlin is still the source of
truth — paste errors back into `.teamcity/settings.kts`. The DSL is
written against `version = "2024.12"` (same as the compose images).

## What you can actually test offline

| Thing | Offline? |
| --- | --- |
| Server UI, agent connected, DSL import | Yes |
| `local-checks`: `docker build` of example-api + `terraform fmt` + `terraform init -backend=false && validate` | Yes. Uses `REPO_HOST_PATH` (set on the compose agent) so the host daemon sees the Dockerfile. Downloads the AWS **provider** plugin; does not call AWS. |
| `make docker-build` / `make docker-run` / `curl :8080/health` | Yes, no TeamCity required |
| `plan` (`terraform plan` against S3 backend + real inventory) | **No.** Needs AWS creds, the state bucket, and the platform stack. Dummy tfvars are enough for **validate**, not for a meaningful plan. |
| `build` (push to ECR) | **No.** Needs AWS and ECR. |
| `apply (*)` to ECS Fargate | **No.** Needs real AWS. |

There is no LocalStack in this repo. LocalStack's ECS Fargate support
is not something we pretend covers this golden path. Apply stays on
AWS.

## plan-only vs apply

`plan` in `.teamcity/settings.kts` is already plan-only: it never
calls `terraform apply` or `aws ecs update-service`. On a real
TeamCity (OIDC role, backend, platform state present) that is the PR
gate.

`local-checks` is the offline stand-in: image build + fmt + validate,
no apply, no ECR, no AWS APIs.

Do not run `apply (prod)` against a real account with the placeholder
account ID still in the roots.

## Cleaning up

`make teamcity-down` keeps named volumes (`teamcity-server-data`,
`teamcity-agent-config`, logs) so the admin user and imported DSL
survive a restart. `make teamcity-reset` destroys them.
