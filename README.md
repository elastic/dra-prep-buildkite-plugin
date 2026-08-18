# dra-prep-buildkite-plugin

Buildkite plugin that runs in the same step as your build to generate DRA (Daily Releasable Artifacts) metadata:

- a build identifier `{version}-{8hex}` (e.g. `9.5.0-025ead4a`)
- `manifest-{stack_version}.json` (schema 2.1.0)
- `summary-{stack_version}.html`

The metadata plus a copy of the build artifacts are written to a DRA tree on disk (`artifacts/dra/{product_id}/{build_id}/`), uploaded to GCS (`gs://elastic-artifacts-{workflow}/dra-builds/{product_id}/{build_number}/{build_id}/`) via Workload Identity Federation, and the build id is exposed to downstream steps via the `DRA_VERSION_BUILD_ID` meta-data.

> **Upgrading from v0.1.2?** v0.1.4 switches the GCS upload to use `cloud.google.com/go/storage` with native Workload Identity Federation — no external tooling required. Ensure your pipeline slug is registered in the [release-artifacts Terraform](https://github.com/elastic/infra/tree/master/terraform/providers/gcp/env/release-artifacts/elastic-release.tfvars) so the WIF IAM binding exists for your slug.

The binary doing the actual work is [`elastic/dractl`](https://github.com/elastic/dractl) (private). This repo is the public Buildkite plugin shell.

## Usage

```yaml
steps:
  - label: ":package: Build apm-server"
    key: build-apm-server
    command: |
      make build
      mkdir -p artifacts
      cp build/distributions/* artifacts/
    plugins:
      - elastic/dra-prep#v0.1.6:
          product_id: apm-server
          stack_version: 9.5.0-SNAPSHOT
          workflow: snapshot
```

The plugin runs after your `command` completes. If the command fails, the plugin skips gracefully.

Artifacts must be staged under `artifacts/` by the build command before the plugin runs. The plugin validates that this directory exists and is non-empty, then passes it to `dractl`, which writes the DRA tree to `artifacts/dra/{product_id}/{build_id}/`.

A downstream step can read the build id:

```yaml
  - label: ":mag: Use build id"
    command: |
      build_id=$(buildkite-agent meta-data get DRA_VERSION_BUILD_ID)
      echo "Build id: $build_id"
    depends_on: "build-apm-server"
```

## Configuration

| Option | Required | Description |
|---|---|---|
| `product_id` | yes | Product identifier, e.g. `apm-server` |
| `stack_version` | yes | Stack version, e.g. `9.5.0-SNAPSHOT` |
| `workflow` | yes | `snapshot` or `staging` |
| `fail_on_diff` | no | Fail the step if `dractl` detects a diff against the previous release's manifest (default `false`) |
| `upload` | no | Upload the DRA tree to GCS after `dractl prep` (default `true`). Set to `false` in CI smoke tests.

## Requirements

The plugin downloads the `dractl` binary at runtime from `elastic/dractl` GitHub Releases. The pipeline's `GithubPermissionSet` must include `elastic/dractl` so the agent has a `VAULT_GITHUB_TOKEN` with read access to that private repo.

The plugin runs on Linux (amd64 and arm64). All Elastic Buildkite agents meet this requirement.

## Release runbook

The plugin version and the `dractl` binary version are released in lockstep:

1. Tag `elastic/dractl` `vX.Y.Z` → GitHub Release publishes archives + `checksums.txt`.
2. Bump `DRACTL_VERSION="vX.Y.Z"` in `hooks/post-command`.
3. Commit, tag this repo `vX.Y.Z`, push.

Consumers on `elastic/dra-prep#vX.Y.Z` automatically pick up the matching binary.

## Development

Install tools via [Hermit](https://cashapp.github.io/hermit/) and run checks:

```bash
source bin/activate-hermit
pre-commit run --all-files  # lint + format
bats tests/                 # unit tests
```
