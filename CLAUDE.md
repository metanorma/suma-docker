# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Docker container for SUMA (STEP Unified Metanorma Architecture) and building ISO 10303 from source. Published as `ghcr.io/metanorma/suma-docker`.

## Build Commands

```bash
# Build the Docker image locally
docker build -t suma:latest .

# Update gems and rebuild image
make update docker

# Run the container interactively
docker run -it --rm ghcr.io/metanorma/suma-docker:latest
```

## Architecture

The Dockerfile layers on `metanorma/metanorma:latest` and installs:

1. **SUMA** and **stepmod-utils** gems (via Bundler)
2. **eengine** — EXPRESS schema engine binary, architecture-aware (x86-64 or arm64)
3. **eep** — x86-64 only binary, runs on ARM64 via QEMU user-mode emulation

The Makefile is a full build system for ISO 10303 document generation. Key build modes:

- `make <part>` — build a single part (e.g., `make event`, `make 10303-47`)
- `make srl` — build the Schema Reference Library (uses a git worktree from `develop`)
- `make smrl` — build the Schema Model Reference Library
- `make remote_feature ROOT=<module>` / `make local_feature ROOT=<module>` — build a feature module with dependencies
- `make diff_collection BRANCH=<branch> REF=<base>` — build only documents that differ between branches

Append `docker` to any build target to run inside the container instead of locally (e.g., `make srl docker`).

## CI/CD

Version is tracked in the `VERSION` file (semver). Publishing workflow:

1. **release-tag** workflow (manual `workflow_dispatch`) — updates VERSION file and pushes a `v*` tag
2. **build-push** workflow — triggers on push to main (publishes `edge` tag) and on `v*` tags (publishes versioned tags). Builds multi-platform (amd64/arm64) and pushes to GHCR only.

To release a new version: run the release-tag workflow with the desired version number.

## Key Details

- The Gemfile pins `connection_pool ~> 2.5` due to a SyntaxError in 3.x with Ruby 3.3.0
- The Makefile scripts/ directory and documents/ directory are expected to exist in the working directory when using build targets — this repo is primarily the container definition
- Feature builds use git worktrees and track state in `.feature-build-worktree`, `.feature-build-module`, `.feature-build-commit` files
- Post-processing defaults to renaming (`POSTPROCESS=rename`), set `POSTPROCESS=smrl` for full SMRL conversion
