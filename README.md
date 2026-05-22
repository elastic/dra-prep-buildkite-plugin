# dra-prep-buildkite-plugin

Buildkite plugin that runs in the same step as your build to generate DRA (Daily Releasable Artifacts) metadata:

- a build identifier `{version}-{8hex}` (e.g. `9.5.0-025ead4a`)
- `manifest-{stack_version}.json` (schema 2.1.0)
- `summary-{stack_version}.html`

All three files plus the build artifacts are uploaded to the Buildkite store. The [DRA processing pipeline](https://github.com/elastic/platform-engineering-productivity) downloads them from the store and ships them to the artifact CDN.

The binary doing the actual work is [`elastic/dractl`](https://github.com/elastic/dractl) (private). This repo is the public Buildkite plugin shell.

## Usage

```yaml
steps:
  - label: ":package: Build apm-server"
    command: make build
    plugins:
      - elastic/vault-secrets#vX.Y.Z:
          path: "secret/ci/elastic/github-readonly"
          field: token
          env_var: GITHUB_TOKEN
      - elastic/dra-prep#v0.1.0:
          product_id: apm-server
          stack_version: 9.5.0-SNAPSHOT
          workflow: snapshot
          artifacts_dir: ./build/distributions
```

The plugin runs after your `command` completes. If the command fails, the plugin skips gracefully.

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
| `artifacts_dir` | yes | Path to the directory containing build artifacts |

## Requirements

The plugin downloads the `dractl` binary at runtime from `elastic/dractl` GitHub Releases. Your step needs a `GITHUB_TOKEN` with read access to private repos. Chain [`elastic/vault-secrets-buildkite-plugin`](https://github.com/elastic/vault-secrets-buildkite-plugin) before this plugin (see usage snippet above).

The plugin runs on Linux (amd64 and arm64). All Elastic Buildkite agents meet this requirement.

## Release runbook

The plugin version and the `dractl` binary version are released in lockstep:

1. Tag `elastic/dractl` `vX.Y.Z` → GitHub Release publishes archives + `checksums.txt`.
2. Bump `DRACTL_VERSION="vX.Y.Z"` in `hooks/post-command`.
3. Commit, tag this repo `vX.Y.Z`, push.

Consumers on `elastic/dra-prep#vX.Y.Z` automatically pick up the matching binary.

## Development

Run tests locally (requires `bats` and `sha256sum`):

```bash
bats tests/
```

Lint the hook:

```bash
shellcheck hooks/post-command
```

Validate the plugin schema:

```bash
# requires buildkite-plugins/plugin-linter installed locally
plugin-linter --name dra-prep
```
