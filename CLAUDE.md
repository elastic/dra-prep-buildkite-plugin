# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A public Buildkite plugin shell. The hook downloads and runs `elastic/dractl` (private Go CLI) to generate DRA (Daily Releasable Artifacts) metadata — build id, manifest, HTML summary — and set the `DRA_VERSION_BUILD_ID` meta-data. The plugin has no Go source; all logic lives in `hooks/post-command` (bash) and `elastic/dractl`.

## Development commands

```bash
source bin/activate-hermit                    # activate hermit env (shellcheck, shfmt, bats, python3.12)
python3.12 -mpip install pre-commit==4.6.0    # install pre-commit under Python 3.12 (not in hermit)
python3.12 -mpre_commit run --all-files       # lint + format (shellcheck, shfmt, yaml checks)
bats tests/                                   # run unit tests
```

## Architecture

- **`hooks/post-command`** — the entire plugin runtime. Validates config, resolves and SHA256-verifies the pinned `dractl` binary from `elastic/dractl` GitHub Releases (via the API asset endpoint, required for private repos), runs `dractl prep` (which writes the DRA tree under `artifacts/dra/{product_id}/{build_id}/`), and sets `DRA_VERSION_BUILD_ID` meta-data read from the generated manifest via `jq`. Does not upload the tree — that is handled by a separate step.
- **`plugin.yml`** — Buildkite plugin schema defining the three required inputs: `product_id`, `stack_version`, `workflow`.
- **`tests/post-command.bats`** — bats tests with a stubbed `curl` (serves pre-built fixture tarballs) and stubbed `buildkite-agent` (logs calls to a file for assertion). The fake `dractl` lives in `tests/fixtures/dractl`.
- **`bin/`** — hermit environment. Managed via `hermit install/remove`; never edit symlinks manually.
- **`.buildkite/pipeline.yml`** — CI entry point triggered by `catalog-info.yaml`. Runs pre-commit and bats on `ubuntu-build-essential`, plugin-linter on a GCP VM.

## CI constraints

- **hermit pre-commit is pinned to Python 3.9**: The hermit `pre-commit` package declares `runtime-dependencies = ["python3@3.9"]` in the upstream cashapp/hermit-packages manifest. Hermit invokes pre-commit via an absolute path to Python 3.9 — adding a `python3@3.12` hermit shim to `bin/` does NOT override this. Adding `language_version: python3.12` to `.pre-commit-config.yaml` doesn't help either, because virtualenv runs inside a pre-commit subprocess that doesn't resolve hermit shims.
- **Workaround**: Remove `pre-commit` from hermit, install `python3@3.12` instead, and invoke pre-commit via pip in CI and locally: `python3.12 -mpip install pre-commit==4.6.0 && python3.12 -mpre_commit run ...` (see `default-pipeline.yml`).
- **CI image has no Python**: `ubuntu-build-essential` ships no Python. All Python in CI comes from hermit.
- **check-buildkite validates all `.buildkite/*.yml` files** with the Buildkite schema vendored in check-jsonschema. As of 0.37.x the vendored schema supports the Elastic-internal `if_changed` extension used in `pipeline.yml`.

## Key conventions

- **Version lockstep**: `DRACTL_VERSION` in `hooks/post-command` must match the plugin git tag. Bump both together at release.
- **Archive name**: `dractl_${DRACTL_VERSION#v}_linux_${arch}.tar.gz` — strips the `v` prefix to match GoReleaser's `{{ .Version }}` output.
- **Auth**: the hook reads `VAULT_GITHUB_TOKEN` (provided automatically by Elastic's Buildkite workers when `elastic/dractl` is in the pipeline's `GithubPermissionSet`). Do not use `GITHUB_TOKEN`.
- **shfmt style**: `shfmt -i 2 -ci` — enforced by pre-commit. Run `shfmt -w -i 2 -ci <file>` after editing shell scripts.
