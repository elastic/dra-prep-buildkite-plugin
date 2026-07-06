# dra-prep-buildkite-plugin

Buildkite plugin that runs in the same step as your build to generate DRA (Daily Releasable Artifacts) metadata:

- a build identifier `{version}-{8hex}` (e.g. `9.5.0-025ead4a`)
- `manifest-{stack_version}.json` (schema 2.1.0)
- `summary-{stack_version}.html`

All three files plus the build artifacts are uploaded to a GCS bucket. A downstream DRA processing pipeline reads them from there and ships them to the artifact CDN.

The binary doing the actual work is [`elastic/dractl`](https://github.com/elastic/dractl) (private). This repo is the public Buildkite plugin shell.

## Usage

```yaml
steps:
  - label: ":package: Build apm-server"
    key: build-apm-server
    command: |
      make build
      mkdir -p dist
      cp build/distributions/* dist/
    plugins:
      - elastic/dra-prep#v0.1.0:
          product_id: apm-server
          stack_version: 9.5.0-SNAPSHOT
          workflow: snapshot
          artifacts_dir: ./dist
```

The plugin runs after your `command` completes. If the command fails, the plugin skips gracefully.

Artifacts must be staged under `artifacts_dir` by the build command before the plugin runs. The plugin validates that this directory exists and is non-empty, then passes it to `dractl` and uploads the resulting DRA tree to:

```
gs://{gcs_bucket}/dra-builds/{BUILDKITE_PIPELINE_SLUG}/{BUILDKITE_BUILD_NUMBER}/{version_build_id}/
```

`BUILDKITE_PIPELINE_SLUG` and `BUILDKITE_BUILD_NUMBER` are set automatically by Buildkite. The build number is included so the downstream DRA processing pipeline can tell apart two builds of the same product for the same stack version.

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
| `artifacts_dir` | yes | Directory containing the flat built artifacts, e.g. `./dist` |

## Requirements

The plugin downloads the `dractl` binary at runtime from `elastic/dractl` GitHub Releases. The pipeline's `GithubPermissionSet` must include `elastic/dractl` so the agent has a `VAULT_GITHUB_TOKEN` with read access to that private repo.

The plugin uploads to GCS via `gcloud storage cp`, authenticated through the shared `dra-build-pipelines` Workload Identity Federation provider. The IAM policy on the target buckets restricts each pipeline to writing under its own `dra-builds/{pipeline-slug}/` prefix.
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
