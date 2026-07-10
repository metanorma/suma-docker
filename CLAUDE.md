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
./tests/smoke.sh suma:test           # Linux smoke (binaries on PATH, --version)
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
`eengine.exe` and `eep.exe` into `C:\Windows` via `curl.exe`. (Earlier versions
used PowerShell `Invoke-WebRequest`, but it sporadically hit TLS errors against
github.com from inside the Windows container; `curl.exe` is more reliable and
ships with Windows Server 2019+.)

Historically this Dockerfile used a separate `mcr.microsoft.com/windows/servercore`
builder stage because gem installation hit ENOTSOCK errors in the runner image.
With `suma` now bundled in the base `metanorma` gem, the builder stage is no
longer needed.

## Test Suite (`tests/`)

Four scripts, all executable, designed to run inside the built image via `docker run`:

- **`tests/smoke.sh`** (Linux) — verifies `eengine`, `eep`, `metanorma`, `suma`
  are on PATH and `metanorma`/`suma` respond to `--version`. Best-effort
  invocation of `eengine`/`eep` with 5s timeouts.
- **`tests/smoke.ps1`** (Windows) — PowerShell port of the above. Run via
  `docker run --rm -v "$PWD\tests:C:\tests" <image> powershell -File C:\tests\smoke.ps1`.
- **`tests/integration.sh`** (Linux) — clones `metanorma/iso-10303` (private;
  uses `GH_TOKEN` env if set) and runs `suma generate-schemas metanorma-smol.yml`
  to exercise the full suma parsing + eengine/eep pipeline without the slow
  document compilation. Runs in ~15s on CI.

CI gating (see `.github/workflows/build-push.yml`):
- Linux PRs: `smoke.sh` only (fast feedback).
- Linux main pushes: `smoke.sh` + `integration.sh` (full validation).
- Linux tag pushes: `smoke.sh` + `integration.sh` gate the multi-arch publish.
- Windows PRs/main/tag: `smoke.ps1` gates the build/publish.

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

Version is tracked in the `VERSION` file. Scheme is aligned with the upstream
metanorma-docker tag:
- `X.Y.Z` (e.g. `1.16.8`) — first release built on top of metanorma-docker `X.Y.Z`
- `X.Y.Z.N` (e.g. `1.16.8.1`) — N-th suma-specific patch on top of the same base
  (eengine bump, Dockerfile fix, etc.)

### Workflows

- **`build-push.yml`** — the main pipeline.
  - `publish-linux` (tag push only): builds amd64 image locally, runs
    `tests/smoke.sh` + `tests/integration.sh`, then builds + pushes the
    multi-arch (`linux/amd64`, `linux/arm64`) image to GHCR. Tags: `latest`,
    `X.Y.Z[.N]`, `X.Y.Z`, `X.Y`, `X`.
  - `publish-windows` (tag push only): matrix on `windows-ltsc2025` and
    `windows-ltsc2022`; builds + pushes per-version tag, then `manifest-windows`
    aggregates them under the bare `windows` tag. Each variant runs
    `tests/smoke.ps1` before push.
  - `release-notes` (tag push only, after publish-linux): creates a GitHub
    Release with image metadata (base image, eengine version, source commit,
    compare link).
  - `build-linux-pr` (PR + main push): validation build + smoke test, no push.
    On main push, also runs integration test.
  - `build-windows-pr` (PR + main push): Windows validation build + smoke test.

- **`release-tag.yml`** (manual `workflow_dispatch`) — takes a version input
  matching `X.Y.Z` or `X.Y.Z.N`, updates `VERSION`, commits (allow-empty), and
  pushes the `v*` tag. This is the only way to cut a release. Auth via
  `METANORMA_CI_PAT_TOKEN` (the `metanorma-ci` user is in the `ci` team which
  has write access).

- **`auto-sync-base-image.yml`** (daily cron + manual) — polls Docker Hub for
  the latest `metanorma/metanorma:X.Y.Z` tag and, when drift is detected vs.
  the `Dockerfile` FROM pin, opens a PR bumping `Dockerfile`,
  `Dockerfile.windows`, and `VERSION`. Auth via `METANORMA_CI_PAT_TOKEN` so
  the PR triggers downstream CI.

### To release a new version

Run the `release-tag` workflow with the desired version (`X.Y.Z` aligned with
the base image, or `X.Y.Z.N` for a suma-specific patch). Do not push tags
manually. The release-tag workflow will commit, tag, push, and the tag push
triggers build-push.yml which publishes to GHCR + creates the GitHub Release.

### Image traceability

Each versioned tag has:
- A GitHub Release (https://github.com/metanorma/suma-docker/releases) with
  image metadata + compare link.
- OCI labels on the image itself: `org.opencontainers.image.revision` (source
  commit), `org.opencontainers.image.version`, etc. Inspect via
  `docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' <image>`.

## Dependabot

`.github/dependabot.yml` watches the `github-actions` and `docker` ecosystems,
opening weekly PRs on Mondays. The `auto-sync-base-image.yml` workflow is the
primary mechanism for base-image updates; Dependabot's `docker` entry is a
backup.
