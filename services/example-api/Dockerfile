# syntax=docker/dockerfile:1
# Multi-stage, non-root, no shell in the runtime image.
# Build: docker build --build-arg VERSION=<git-sha> -t example-api:local .

FROM golang:1.24-alpine AS build
WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY *.go ./
ARG VERSION=dev
ARG SERVICE_NAME=example-api
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/api .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=build /out/api /api

# Baked in at image build; runtime can still override.
ARG VERSION=dev
ARG SERVICE_NAME=example-api
ENV VERSION=${VERSION}
ENV SERVICE_NAME=${SERVICE_NAME}
ENV PORT=8080

USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/api"]
