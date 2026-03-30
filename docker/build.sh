#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/brdelphus}"
IMAGE="${IMAGE:-caddy-custom}"
TAG="${TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/arm64,linux/amd64}"

FULL_IMAGE="${REGISTRY}/${IMAGE}:${TAG}"

echo "Building ${FULL_IMAGE} for ${PLATFORMS}"

docker buildx build \
  --platform "${PLATFORMS}" \
  --file "$(dirname "$0")/Dockerfile" \
  --tag "${FULL_IMAGE}" \
  --push \
  "$(dirname "$0")"

echo "Done: ${FULL_IMAGE}"
