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
docker build -t suma:test --build-arg BASE_IMAGE=metanorma/metanorma:windows-ltsc2022-1.16.6 -f Dockerfile.windows .

# Rebuild the local Docker image after pulling upstream changes
make update docker

# Run the container interactively
docker run -it --rm ghcr.io/metanorma/suma-docker:latest
```

## Image Architecture

Both Dockerfiles share the same purpose: take the metanorma base image and add
`eengine` + `eep`. No gem installation happens in this repo.

### Linux `Dockerfile`

Layers on `metanorma/metanorma:1.16.6` (pinned, not `latest`). Adds:

1. **`eengine`** (EXPRESS schema engine) — architecture-aware: pulls `x86-64` or
   `arm64` SBCL binary based on `uname -m`. Version pinned via `EENGINE_VERSION`
   build-arg (currently `5.2.7`).
2. **`eep`** (Eurostep EXPRESS Parser) — `x86-64` ELF binary. On `aarch64` hosts
   the image installs `qemu-user-static`, `libc6:amd64`, and `binutils:amd64` so
   the x86-64 eep binary runs transparently under QEMU user-mode emulation. No
   setup is needed on Apple Silicon Macs.

### `Dockerfile.windows`

Single-stage build on `metanorma/metanorma:windows-ltsc2025-1.16.6`. Downloads
`eengine.exe` and `eep.exe` into `C:\Windows` via PowerShell `Invoke-WebRequest`.

Historically this Dockerfile used a separate `mcr.microsoft.com/windows/servercore`
builder stage because gem installation hit ENOTSOCK errors in the runner image.
With `suma` now bundled in the base `metanorma` gem, the builder stage is no
longer needed.

## Makefile Build System

The Makefile is a full build system for ISO 10303 document generation. It detects
the host OS (`linux` / `macos` / `windows`) and branches accordingly. Append
`docker` to any target to run it inside the container instead of locally
(e.g. `make srl docker`).

Key targets:

- `make <part>` — build a single part (e.g. `make event`, `make 10303-47`)
- `make single-pattern '<glob>'` — build matching documents as a collection
- `make srl` — Schema Reference Library. Creates a git worktree from `develop`
  at `$HOME/work/wg12-step-build-srl` (override with `SRL_WORKTREE_BASE=...`),
  copies uncommitted changes into it, builds, then runs
  `scripts/suma2smrl.sh --publish --ci-repo ../wg12-ci`.
- `make smrl` — Schema Model Reference Library (uses `metanorma-smrl-all.yml`)
- `make remote_feature ROOT=<module>` / `make local_feature ROOT=<module>` —
  build a feature module with dependencies. `local_feature` includes
  uncommitted changes; `remote_feature` builds from HEAD only.
- `make rebuild-feature` / `make rebuild-feature-quick` — re-run a feature
  build. `quick` reuses the existing worktree and skips eengine.
- `make diff_collection BRANCH=<branch> REF=<base>` — build only documents
  that differ. `REF` defaults to `develop`.

### Cross-worktree Gemfile pattern

When the Makefile invokes `suma` inside a worktree (srl, feature, diff builds),
it sets `BUNDLE_GEMFILE=$(CURDIR)/Gemfile` so the worktree uses CURDIR's locked
gems. This refers to the **consumer repo's** Gemfile (e.g. iso-10303's), not
this repo — this repo has no Gemfile. `make update` (without `docker`) runs
`bundle update` against that same consumer Gemfile.

### Feature build state files

Feature builds track state in dotfiles at the repo root:
`.feature-build-worktree`, `.feature-build-module`, `.feature-build-commit`.
Diff builds use `.diff-build-worktree`. All are gitignored.

### Post-processing modes

`POSTPROCESS` controls the post-build step:

- `rename` (default) — `scripts/rename_feature_docs.py` renames output to ISO
  document format.
- `smrl` — full SMRL conversion via `scripts/suma2smrl.sh`.

### Python

Makefile post-processing uses Python. If `~/venvs/wg12-step/bin/python3`
exists it is used; otherwise it falls back to system `python3` (or `python`
on Windows).

## CI/CD

Version is tracked in the `VERSION` file (semver, currently `0.1.0`).

- **build-push** workflow — triggers on push to `main` (publishes `latest`)
  and on `v*` tags (publishes semver variants like `1.0`, `1`). Builds
  multi-platform (`linux/amd64`, `linux/arm64`) via QEMU and pushes to GHCR
  only. PRs trigger a validation-only build (no push). Path filters cover
  `Dockerfile`, `Dockerfile.windows`, `VERSION`, and the workflow itself.
- **release-tag** workflow (manual `workflow_dispatch`) — takes a semver
  input, updates `VERSION`, commits, and pushes the `v*` tag. This is the
  only way to cut a release.

**Windows CI is currently disabled** — the `publish-windows`,
`manifest-windows`, and `build-windows-pr` jobs are commented out in
`.github/workflows/build-push.yml`. They were disabled due to Ruby SSL/socket
issues that blocked `gem install` in the runner image. With `suma` now
bundled in the base `metanorma` gem, that blocker no longer applies —
re-enabling Windows CI is a viable follow-up.

To release a new version: run the `release-tag` workflow with the desired
semver number. Do not push tags manually.

## Network access

Cloud sessions and CI can reach `ghcr.io` only if the environment's network
**egress policy** permits it. A normal in-repo `docker build` does **not** need
`ghcr.io` — the base image comes from Docker Hub and the `eengine`/`eep`
binaries come from `github.com`. Only *pulling* or *monitoring* the published
`ghcr.io/metanorma/suma-docker` image touches GHCR.

If a session is blocked from GHCR you'll see:

```
Error: Blocked by session's egress policy
Proxy Response: 403 on CONNECT to ghcr.io:443
```

This is **not** something a repo change can fix — the block is enforced by the
sandbox proxy and must be changed in the Claude Code environment settings:
claude.ai/code → environment selector (the cloud icon) → the environment's
overflow menu (`⋯`) → **Update cloud environment** → **Network access**. Choose
**Custom** and add `ghcr.io` (leave *"Also include default list of common
package managers"* checked), or choose **Full**. `ghcr.io` is nominally part of
the default **Trusted** allowlist, but if a Trusted environment still returns a
`403`, set it explicitly via Custom or Full. Network-policy changes apply to
**new** sessions only, not the session that is already running.
