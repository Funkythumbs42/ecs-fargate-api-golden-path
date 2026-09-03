# Local TeamCity (containers)

Run a throwaway TeamCity server + agent on your machine to click through
this **factory** repo's Kotlin DSL (`new-api`, `local-checks`, platform
apply). App pipelines live in the generated app repo after `new-api`.
This is not production CI and it is not a substitute for AWS.

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

## Load this factory's Kotlin DSL

The server and agent both see this checkout at **the same host path**
(`HOST_REPO_PATH`, printed by `make teamcity-up` and stored in `.env`).
A Git VCS root needs a Git directory; if this tree is not a repo yet,
init one locally.

1. Administration → **Create project** → Manually. Name it `api-factory`.
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
4. TeamCity will import `settings.kts` and create `new-api`,
   `local-checks`, `platform plan/apply`.

App projects are **not** generated from this factory checkout. After
you run `new-api` (needs `gh` on the agent plus TeamCity REST from the
build), a separate project is registered whose VCS root is the **app**
GitHub repo. If REST did not enable versioned settings, one-time UI:

1. Open the app project
2. VCS root → the app GitHub URL
3. Versioned Settings → Kotlin, path `.teamcity`, import from VCS

Then Run **create (dev)** on that app project for the first AWS deploy.

If versioned settings fail to parse, the Kotlin is still the source of
truth — paste errors back into `.teamcity/settings.kts`. The DSL is
written against `version = "2024.12"` (same as the compose images).
Build types are classes, not top-level `object`s. `.teamcity/pom.xml`
must exist so the DSL compiles.

## What you can actually test offline

| Thing | Offline? |
| --- | --- |
| Server UI, agent connected, factory DSL import | Yes |
| `local-checks`: `docker build` of `templates/service-api` + `terraform fmt` + `terraform init -backend=false && validate` | Yes. Uses `REPO_HOST_PATH` (set on the compose agent) so the host daemon sees the Dockerfile. Downloads the AWS **provider** plugin; does not call AWS. |
| `make docker-build` / `make docker-run` / `curl :8080/health` | Yes, no TeamCity required |
| `new-api` GitHub create + TeamCity project register | Needs `gh` auth and a reachable TeamCity URL |
| App `create (dev)` / `ship` to ECS Fargate | **No.** Needs AWS, ECR, platform stack. |

There is no LocalStack in this repo. Apply stays on AWS.

## plan-only vs apply

Factory `platform plan (dev)` never calls `terraform apply` or
`aws ecs update-service`. App `code plan` is the PR gate in the app
repo.

`local-checks` is the offline stand-in: image build + fmt + validate,
no apply, no ECR, no AWS APIs.

Do not run `platform apply (prod)` against a real account with the
placeholder account ID still in the roots. Do not destroy the live
PoC NAT/ALB/ECS in eu-west-1 from this laptop flow.

## Cleaning up

`make teamcity-down` keeps named volumes (`teamcity-server-data`,
`teamcity-agent-config`, logs) so the admin user and imported DSL
survive a restart. `make teamcity-reset` destroys them.
