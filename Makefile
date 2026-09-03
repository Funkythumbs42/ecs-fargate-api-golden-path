# Golden-path helpers. Run from the factory repo root.
# terraform is expected on PATH (see .terraform-version).

IMAGE        ?= example-api
TAG          ?= local
DOCKER       ?= docker
COMPOSE      ?= $(DOCKER) compose
SERVICE_DIR  := templates/service-api
TF_DIRS      := modules/ecs-api modules/platform \
	platform/envs/dev platform/envs/staging platform/envs/prod

.PHONY: help docker-build docker-run tf-fmt tf-validate local-checks \
	teamcity-up teamcity-down teamcity-reset teamcity-logs new-service inception

help:
	@echo "docker-build     Build the template app image locally"
	@echo "docker-run       Run the image on :8080 (SERVICE_NAME, VERSION from TAG)"
	@echo "tf-fmt           terraform fmt -recursive"
	@echo "tf-validate      terraform init -backend=false && validate in each factory root/module"
	@echo "                 validate may fail without provider download or AWS creds; still the target."
	@echo "local-checks     docker-build + fmt -check + validate (offline-ish)"
	@echo "teamcity-up      Start local TeamCity server (:8111) + agent (docker.sock)"
	@echo "teamcity-down    Stop TeamCity; keep named volumes"
	@echo "teamcity-reset   Stop TeamCity and delete volumes (new wizard next up)"
	@echo "teamcity-logs    Follow TeamCity compose logs"
	@echo "new-service      Render templates/service-api into DEST= (NAME= DEST=)"
	@echo "inception        From-nothing: GitHub app repo + TeamCity project (NAME= GIT_MODE=create)"

docker-build:
	$(DOCKER) build \
		--build-arg VERSION=$(TAG) \
		--build-arg SERVICE_NAME=$(IMAGE) \
		-t $(IMAGE):$(TAG) \
		$(SERVICE_DIR)

docker-run:
	$(DOCKER) run --rm -p 8080:8080 \
		-e SERVICE_NAME=$(IMAGE) \
		-e VERSION=$(TAG) \
		$(IMAGE):$(TAG)

tf-fmt:
	terraform fmt -recursive

tf-validate:
	@set -e; \
	for d in $(TF_DIRS); do \
		echo "==> validate $$d"; \
		( cd $$d && terraform init -backend=false -input=false -no-color && terraform validate -no-color ); \
	done

local-checks:
	REPO_HOST_PATH="$(PWD)" IMAGE=$(IMAGE) TAG=$(TAG) ./scripts/local-checks.sh

# Absolute path so docker.sock builds resolve. Also written to .env because
# `sudo docker compose` does not inherit PWD/HOST_REPO_PATH from the caller.
HOST_REPO_PATH ?= $(abspath .)

teamcity-up:
	@printf 'HOST_REPO_PATH=%s\n' '$(HOST_REPO_PATH)' > .env
	@echo "TeamCity UI: http://localhost:8111"
	@echo "file:// VCS root and REPO_HOST_PATH: $(HOST_REPO_PATH)"
	@echo "First start is slow and wants ~4GB RAM. See LOCAL_TEAMCITY.md."
	HOST_REPO_PATH="$(HOST_REPO_PATH)" $(COMPOSE) up -d

teamcity-down:
	@printf 'HOST_REPO_PATH=%s\n' '$(HOST_REPO_PATH)' > .env
	HOST_REPO_PATH="$(HOST_REPO_PATH)" $(COMPOSE) down

teamcity-reset:
	@printf 'HOST_REPO_PATH=%s\n' '$(HOST_REPO_PATH)' > .env
	HOST_REPO_PATH="$(HOST_REPO_PATH)" $(COMPOSE) down -v
	rm -f .env

teamcity-logs:
	HOST_REPO_PATH="$(HOST_REPO_PATH)" $(COMPOSE) logs -f

# NAME=orders-api DEST=/tmp/orders-api make new-service
new-service:
	@test -n "$(NAME)" || (echo "NAME is required, e.g. make new-service NAME=orders-api DEST=/tmp/orders-api" >&2; exit 1)
	@test -n "$(DEST)" || (echo "DEST is required, e.g. make new-service NAME=orders-api DEST=/tmp/orders-api" >&2; exit 1)
	./scripts/new-service.sh $(NAME) $(DEST)

# NAME=orders-api make inception
# PORT=8080 PRESET=small ALB_INTERNAL=false GIT_MODE=create|existing GIT_REPO=owner/name
inception:
	@test -n "$(NAME)" || (echo "NAME is required, e.g. make inception NAME=orders-api" >&2; exit 1)
	GIT_MODE=$(or $(GIT_MODE),create) GIT_REPO=$(GIT_REPO) ALB_INTERNAL=$(or $(ALB_INTERNAL),false) \
		./scripts/inception.sh $(NAME) $(or $(PORT),8080) $(or $(PRESET),small) "$(HOST)" $(or $(GIT_MODE),create) "$(GIT_REPO)" $(or $(ALB_INTERNAL),false)
