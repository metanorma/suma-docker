# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repo publishes the Docker image `ghcr.io/metanorma/suma-docker`, which adds the
EXPRESS schema tooling — `eengine` and `eep` — on top of the
[metanorma-docker](https://github.com/metanorma/metanorma-docker) base image. SUMA
itself ships with the `metanorma` gem and is therefore already present in the base
image; this repo installs no gems and ships no `Gemfile`.

The `Makefile`, `scripts/`, and `documents/` referenced by build targets are expected
to live in the working directory at runtime (typically a checkout of the `iso-10303`
repo) — not in this repo. The Makefile is the canonical build orchestrator that gets
re-used by downstream ISO 10303 builds.

## Build Commands

```bash
# Build the Linux image locally
docker build -t suma:latest .

# Build the Windows image (requires a Windows host in Windows Containers mode)
docker build -t suma:windows -f Dockerfile.windows .

# Override the pinned base image (e.g. to test against another metanorma release)
docker build -t suma:test --build-arg BASE_IMAGE=metanorma/metanorma:windows-ltsc2022-1.16.8 -f Dockerfile.windows .

# Rebuild the local Docker image after pulling upstream changes
make update docker

# Run the container interactively
docker run -it --rm ghcr.io/metanorma/suma-docker:latest

# Run the test suite locally against a built image
docker build -t suma:test .
./tests/smoke.sh suma:test           # Linux smoke (reads tests/smoke.contract)
./tests/integration.sh suma:test     # Integration (suma generate-schemas on iso-10303-smol)
```

## Image Architecture

Both Dockerfiles share the same purpose: take the metanorma base image and add
`eengine` + `eep`. No gem installation happens in this repo.

### Linux `Dockerfile`

Layers on `metanorma/metanorma:1.16.8` (pinned, not `latest`). Adds:

1. **`eengine`** (EXPRESS schema engine) — architecture-aware: pulls `x86-64` or
   `arm64` SBCL binary based on `uname -m`. Version pinned via `EENGINE_VERSION`
   build-arg (currently `5.2.7`).
2. **`eep`** (Eurostep EXPRESS Parser) — `x86-64` ELF binary. On `aarch64` hosts
   the image installs `qemu-user-static`, `libc6:amd64`, and `binutils:amd64` so
   the x86-64 eep binary runs transparently under QEMU user-mode emulation. No
   setup is needed on Apple Silicon Macs.

### `Dockerfile.windows`

Single-stage build on `metanorma/metanorma:windows-ltsc2025-1.16.8`. Downloads
`eengine.exe` and `eep.exe` into `C:\Windows` via `curl.exe`.

## Test Suite (`tests/`)

### Smoke contract

`tests/smoke.contract` is the single source of truth for what every suma-docker
image must satisfy at runtime. Line-based format with three check types:
`exists <binary>`, `succeeds <cmd>`, `best_effort <cmd>`. Both adapters consume
it — adding a new invariant means editing this file once, not two scripts.

### Adapters

- **`tests/smoke.sh`** (Linux) — reads the contract, pipes it into the container
  via stdin. Usage: `./tests/smoke.sh <image>`.
- **`tests/smoke.ps1`** (Windows, in-container) — reads the contract from
  `C:\tests\smoke.contract` (mounted from the host). Usage: invoked by
  `tests/smoke-windows.ps1` (see below).
- **`tests/smoke-windows.ps1`** (Windows, host-side wrapper) — takes an `-Image`
  parameter, does the docker run + volume mount + invokes smoke.ps1. Mirrors the
  smoke.sh interface. Usage: `./tests/smoke-windows.ps1 -Image <tag>`.

### Integration test

- **`tests/integration.sh`** (Linux) — clones `metanorma/iso-10303` (private;
  uses `GH_TOKEN` env if set) and runs `suma generate-schemas metanorma-smol.yml`
  to exercise the full suma parsing + eengine/eep pipeline without the slow
  document compilation. Runs in ~15s on CI.

### CI gating

- Linux PRs: smoke only (fast feedback).
- Linux main pushes: smoke + integration.
- Linux tag pushes: smoke + integration gate the multi-arch publish.
- Windows PRs/main/tag: smoke gates the build/publish.
- Windows jobs include a "wait for Docker daemon" step (60s retry loop) because
  Windows runners sometimes boot without Docker service ready.

## Reusable Scripts and Actions

- **`.github/scripts/image-metadata.sh`** — single source of truth for image
  metadata extracted from `VERSION` and `Dockerfile(s)`. Outputs `KEY=VALUE`
  lines on stdout. Used by `build-push.yml` (job_info + release-notes) and
  `auto-sync-*.yml` workflows. Has its own test: `tests/test-image-metadata.sh`.

- **`.github/scripts/latest-release.sh`** — fetches the latest stable version tag
  from Docker Hub (`dockerhub:owner/repo`) or GitHub Releases
  (`github:owner/repo`). Used by both auto-sync workflows.

- **`.github/actions/setup-build-env/`** — composite action that wraps
  checkout + optionally QEMU + Buildx + GHCR login. Used by all build jobs in
  `build-push.yml`. Takes `with-qemu`, `with-buildx`, `with-login` booleans.

## Makefile Build System

The Makefile is a full build system for ISO 10303 document generation. It detects
the host OS (`linux` / `macos` / `windows`) and branches accordingly. Append
`docker` to any target to run it inside the container instead of locally
(e.g. `make srl docker`).

### Dispatch macros

OS/docker dispatch is consolidated into two top-level variables:

- **`SUMA_BUILD_RUN`** — picks `bundle exec suma build` (local) or
  `docker run ... suma build` (when `docker` is in MAKECMDGOALS). Linux always
  uses bundle exec; macOS/Windows pick docker if requested.
- **`UPDATE_RUN`** — picks `docker build` or `bundle update && fontist update`.

Each build target calls `$(call suma-build,<manifest>,<workdir>,<logfile>)` —
one line replaces what used to be ~25 lines of OS-branching per target.

### Key targets

- `make <part>` — build a single part (e.g. `make event`, `make 10303-47`)
- `make single-pattern '<glob>'` — build matching documents as a collection
- `make srl` — Schema Reference Library. Creates a git worktree from `develop`
  at `$HOME/work/wg12-step-build-srl` (override with `SRL_WORKTREE_BASE=...`).
- `make smrl` — Schema Model Reference Library (uses `metanorma-smrl-all.yml`)
- `make remote_feature ROOT=<module>` / `make local_feature ROOT=<module>` —
  build a feature module with dependencies.
- `make rebuild-feature` / `make rebuild-feature-quick` — re-run a feature build.
- `make diff_collection BRANCH=<branch> REF=<base>` — build only documents
  that differ. `REF` defaults to `develop`.

### Cross-worktree Gemfile pattern

When the Makefile invokes `suma` inside a worktree (srl, feature, diff builds),
it sets `BUNDLE_GEMFILE=$(CURDIR)/Gemfile` so the worktree uses CURDIR's locked
gems. This refers to the **consumer repo's** Gemfile (e.g. iso-10303's), not
this repo — this repo has no Gemfile.

### Feature build state files

Feature builds track state in dotfiles at the repo root:
`.feature-build-worktree`, `.feature-build-module`, `.feature-build-commit`.
Diff builds use `.diff-build-worktree`. All are gitignored.

### Post-processing modes

`POSTPROCESS` controls the post-build step:

- `rename` (default) — `scripts/rename_feature_docs.py` renames output to ISO
  document format.
- `smrl` — full SMRL conversion via `scripts/suma2smrl.sh`.

## CI/CD

Version is tracked in the `VERSION` file. Scheme is aligned with the upstream
metanorma-docker tag:
- `X.Y.Z` (e.g. `1.16.8`) — first release built on top of metanorma-docker `X.Y.Z`
- `X.Y.Z.N` (e.g. `1.16.8.1`) — N-th suma-specific patch on top of the same base
  (eengine bump, Dockerfile fix, etc.)

`latest` only updates on tag pushes, not on main pushes — it always points at the
most recent tagged release.

### Workflows

- **`build-push.yml`** — the main pipeline.
  - `publish-linux` (tag push only): builds amd64 image locally, runs smoke +
    integration tests, then builds + pushes multi-arch to GHCR. Tags: `latest`,
    `X.Y.Z[.N]`, `X.Y.Z`, `X.Y`, `X`.
  - `publish-windows` (tag push only): matrix on ltsc2025 and ltsc2022; each
    variant runs smoke before push. `manifest-windows` aggregates them under
    the bare `windows` tag.
  - `release-notes` (tag push only, after publish-linux): creates a GitHub
    Release with image metadata + compare link.
  - `build-linux-pr` (PR + main push): validation build + smoke + (on main)
    integration test. No push.
  - `build-windows-pr` (PR + main push): Windows validation build + smoke. No push.
  - Windows jobs include a "Wait for Docker daemon" retry loop (bash, 60s).

- **`release-tag.yml`** (manual `workflow_dispatch`) — takes a version input
  matching `X.Y.Z` or `X.Y.Z.N`, updates `VERSION`, commits (allow-empty), and
  pushes the `v*` tag. Auth via `METANORMA_CI_PAT_TOKEN`.

- **`auto-sync-base-image.yml`** (daily cron + manual) — polls Docker Hub for
  the latest `metanorma/metanorma` tag. When drift is detected, opens a PR
  bumping `Dockerfile`, `Dockerfile.windows`, and `VERSION`.

- **`auto-sync-eengine.yml`** (daily cron + manual) — polls expresslang/eengine-
  releases GitHub Releases for the latest eengine version. When drift is
  detected, opens a PR bumping `EENGINE_VERSION` in both Dockerfiles.

### To release a new version

Run the `release-tag` workflow with the desired version (`X.Y.Z` aligned with
the base image, or `X.Y.Z.N` for a suma-specific patch). Do not push tags
manually.

### Image traceability

Each versioned tag has:
- A GitHub Release with image metadata + compare link.
- OCI labels on the image: `org.opencontainers.image.revision` (source commit),
  `org.opencontainers.image.version`, etc.

## Dependabot

`.github/dependabot.yml` watches the `github-actions` and `docker` ecosystems,
opening weekly PRs on Mondays.
