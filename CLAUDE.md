# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A public Buildkite plugin shell. The hook downloads and runs `elastic/dractl` (private Go CLI) to generate DRA (Daily Releasable Artifacts) metadata — build id, manifest, HTML summary — and upload them to the Buildkite store. The plugin has no Go source; all logic lives in `hooks/post-command` (bash) and `elastic/dractl`.

## Development commands

```bash
source bin/activate-hermit      # activate hermit env (shellcheck, shfmt, bats, pre-commit)
pre-commit run --all-files      # lint + format (shellcheck, shfmt, yaml checks)
bats tests/                     # run unit tests
```

## Architecture

- **`hooks/post-command`** — the entire plugin runtime. Validates config, downloads and SHA256-verifies the pinned `dractl` binary from GitHub Releases, runs `dractl prep`, sets `DRA_VERSION_BUILD_ID` meta-data, and uploads `dra/**/*` artifacts.
- **`plugin.yml`** — Buildkite plugin schema defining the three required inputs: `product_id`, `stack_version`, `workflow`.
- **`tests/post-command.bats`** — bats tests with a stubbed `curl` (serves pre-built fixture tarballs) and stubbed `buildkite-agent` (logs calls to a file for assertion). The fake `dractl` lives in `tests/fixtures/dractl`.
- **`bin/`** — hermit environment. Managed via `hermit install/remove`; never edit symlinks manually.
- **`.buildkite/pipeline.yml`** — CI entry point triggered by `catalog-info.yaml`. Runs pre-commit and bats on `ubuntu-build-essential`, plugin-linter on a GCP VM.

## Key conventions

- **Version lockstep**: `DRACTL_VERSION` in `hooks/post-command` must match the plugin git tag. Bump both together at release.
- **Archive name**: `dractl_${DRACTL_VERSION#v}_linux_${arch}.tar.gz` — strips the `v` prefix to match GoReleaser's `{{ .Version }}` output.
- **Auth**: the hook reads `VAULT_GITHUB_TOKEN` (provided automatically by Elastic's Buildkite workers when `elastic/dractl` is in the pipeline's `GithubPermissionSet`). Do not use `GITHUB_TOKEN`.
- **shfmt style**: `shfmt -i 2 -ci` — enforced by pre-commit. Run `shfmt -w -i 2 -ci <file>` after editing shell scripts.
