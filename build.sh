#!/usr/bin/env bash
set -euo pipefail

# Init builder
docker buildx create --use

# Build for multiple arch (almost needed since Mac M1)
docker buildx build --platform linux/arm64/v8,linux/amd64 -t lucj/argocd-plugin-helmfile:v0.0.1 . --push
