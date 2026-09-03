IMAGE ?= example-api
TAG   ?= local
DOCKER ?= docker

.PHONY: docker-build docker-run

docker-build:
	$(DOCKER) build \
		--build-arg VERSION=$(TAG) \
		--build-arg SERVICE_NAME=$(IMAGE) \
		-t $(IMAGE):$(TAG) \
		.

docker-run:
	$(DOCKER) run --rm -p 8080:8080 \
		-e SERVICE_NAME=$(IMAGE) \
		-e VERSION=$(TAG) \
		$(IMAGE):$(TAG)
