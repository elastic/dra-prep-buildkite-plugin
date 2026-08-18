#!/usr/bin/env bats

HOOK="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/hooks/post-command"
FIXTURES_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/fixtures" && pwd)"

setup() {
  export STUB_DIR
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-dra-XXXXXX")"
  export WORK_DIR
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-dra-XXXXXX")"

  cd "${WORK_DIR}"

  # Default required env vars
  export BUILDKITE_COMMAND_EXIT_STATUS=0
  export BUILDKITE_PLUGIN_DRA_PREP_PRODUCT_ID=apm-server
  export BUILDKITE_PLUGIN_DRA_PREP_STACK_VERSION=9.5.0-SNAPSHOT
  export BUILDKITE_PLUGIN_DRA_PREP_WORKFLOW=snapshot
  export VAULT_GITHUB_TOKEN=fake-token
  export BUILDKITE_BRANCH=main
  export BUILDKITE_COMMIT=abc123
  export BUILDKITE_PIPELINE_SLUG=apm-server
  export BUILDKITE_BUILD_NUMBER=42
  export DRACTL_ARGS_LOG="${STUB_DIR}/dractl-args.log"

  # Determine the arch the hook will request (matches hook's uname logic)
  case "$(uname -m)" in
    x86_64) local arch="amd64" ;;
    aarch64 | arm64) local arch="arm64" ;;
    *) local arch="amd64" ;;
  esac

  # Build a real tarball from the fake dractl fixture (name matches goreleaser template)
  local version="0.1.6"
  local archive="dractl_${version}_linux_${arch}.tar.gz"
  tar -czf "${STUB_DIR}/${archive}" \
    -C "${FIXTURES_DIR}" dractl

  # Compute its real sha256 for checksums.txt
  local sha256
  sha256="$(sha256sum "${STUB_DIR}/${archive}" | awk '{print $1}')"
  echo "${sha256}  ${archive}" >"${STUB_DIR}/checksums.txt"

  # Fake GitHub "releases/tags/..." response: maps asset names to fake
  # per-asset API URLs, mirroring the real API's asset-resolution flow used
  # for private repos.
  cat >"${STUB_DIR}/release.json" <<EOF
{
  "assets": [
    {"name": "${archive}", "url": "https://api.github.com/repos/elastic/dractl/releases/assets/1"},
    {"name": "checksums.txt", "url": "https://api.github.com/repos/elastic/dractl/releases/assets/2"}
  ]
}
EOF

  # Stub curl: serves the fake release metadata for the "tags" lookup, and
  # copies the matching fixture file for each per-asset download URL.
  cat >"${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
output_file=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output_file="$2"; shift 2 ;;
    -H) shift 2 ;;
    https://*) url="$1"; shift ;;
    -*) shift ;;
    *) shift ;;
  esac
done

case "${url}" in
  */releases/tags/*) cat "${CURL_STUB_DIR}/release.json" ;;
  */releases/assets/1) cp "${CURL_STUB_DIR}/${ARCHIVE_NAME}" "${output_file}" ;;
  */releases/assets/2) cp "${CURL_STUB_DIR}/checksums.txt" "${output_file}" ;;
  *)
    echo "unstubbed curl request: ${url}" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${STUB_DIR}/curl"
  export CURL_STUB_DIR="${STUB_DIR}"
  export ARCHIVE_NAME="${archive}"

  # Stub buildkite-agent: no real agent is running in tests, so replace it with a
  # fake that records every invocation. Tests assert the hook called the right
  # subcommands (meta-data set) with the right arguments.
  export AGENT_LOG="${STUB_DIR}/buildkite-agent.log"
  cat >"${STUB_DIR}/buildkite-agent" <<'EOF'
#!/usr/bin/env bash
echo "buildkite-agent $*" >> "${AGENT_LOG}"
EOF
  chmod +x "${STUB_DIR}/buildkite-agent"

  export PATH="${STUB_DIR}:${PATH}"
}

teardown() {
  cd "${TMPDIR:-/tmp}"
  rm -rf "${WORK_DIR}" "${STUB_DIR}"
}

@test "skips when producer step failed" {
  export BUILDKITE_COMMAND_EXIT_STATUS=1
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "skip"
}

@test "fails with clear error when product_id is missing" {
  unset BUILDKITE_PLUGIN_DRA_PREP_PRODUCT_ID
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "product_id"
}

@test "fails with GithubPermissionSet hint when VAULT_GITHUB_TOKEN is missing" {
  unset VAULT_GITHUB_TOKEN
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "GithubPermissionSet"
}

@test "fails when artifacts directory is absent or empty" {
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "artifacts"
}

@test "downloads, verifies, and runs dractl on happy path" {
  mkdir -p ./artifacts
  touch ./artifacts/apm-server-9.5.0-SNAPSHOT-amd64.deb
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  grep -q "meta-data set DRA_VERSION_BUILD_ID 9.5.0-ab12cd34" "${AGENT_LOG}"
  grep -q "upload.*--pipeline-slug apm-server.*--build-number 42" "${DRACTL_ARGS_LOG}"
}

@test "passes --fail-on-diff to dractl when fail_on_diff is true" {
  export BUILDKITE_PLUGIN_DRA_PREP_FAIL_ON_DIFF=true
  mkdir -p ./artifacts
  touch ./artifacts/apm-server-9.5.0-SNAPSHOT-amd64.deb
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  grep -q -- "--fail-on-diff" "${DRACTL_ARGS_LOG}"
}

@test "normalizes raw version to include -SNAPSHOT suffix for snapshot workflow" {
  export BUILDKITE_PLUGIN_DRA_PREP_STACK_VERSION=9.5.0
  export BUILDKITE_PLUGIN_DRA_PREP_WORKFLOW=snapshot
  mkdir -p ./artifacts
  touch ./artifacts/apm-server-9.5.0-SNAPSHOT-amd64.deb
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  grep -q -- "--stack-version 9.5.0-SNAPSHOT" "${DRACTL_ARGS_LOG}"
}

@test "does not duplicate -SNAPSHOT suffix when already present" {
  export BUILDKITE_PLUGIN_DRA_PREP_STACK_VERSION=9.5.0-SNAPSHOT
  export BUILDKITE_PLUGIN_DRA_PREP_WORKFLOW=snapshot
  mkdir -p ./artifacts
  touch ./artifacts/apm-server-9.5.0-SNAPSHOT-amd64.deb
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  grep -q -- "--stack-version 9.5.0-SNAPSHOT" "${DRACTL_ARGS_LOG}"
  ! grep -q -- "--stack-version 9.5.0-SNAPSHOT-SNAPSHOT" "${DRACTL_ARGS_LOG}"
}

@test "skips upload when upload is false" {
  export BUILDKITE_PLUGIN_DRA_PREP_UPLOAD=false
  mkdir -p ./artifacts
  touch ./artifacts/apm-server-9.5.0-SNAPSHOT-amd64.deb
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "skip"
  ! grep -q "^upload" "${DRACTL_ARGS_LOG}"
}
