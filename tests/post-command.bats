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
  export BUILDKITE_PLUGIN_DRA_PREP_ARTIFACTS_DIR="${WORK_DIR}/artifacts"
  export VAULT_GITHUB_TOKEN=fake-token
  export BUILDKITE_BRANCH=main
  export BUILDKITE_COMMIT=abc123
  export BUILDKITE_PIPELINE_SLUG=apm-server
  export BUILDKITE_BUILD_NUMBER=11

  # Seed artifacts dir with a flat artifact (what the producer step produces)
  mkdir -p "${BUILDKITE_PLUGIN_DRA_PREP_ARTIFACTS_DIR}"
  touch "${BUILDKITE_PLUGIN_DRA_PREP_ARTIFACTS_DIR}/apm-server-9.5.0-SNAPSHOT-linux-x86_64.tar.gz"

  # Determine the arch the hook will request (matches hook's uname logic)
  case "$(uname -m)" in
    x86_64) local arch="amd64" ;;
    aarch64 | arm64) local arch="arm64" ;;
    *) local arch="amd64" ;;
  esac

  # Build a real tarball from the fake dractl fixture (name matches goreleaser template)
  local version="0.1.0"
  local archive="dractl_${version}_linux_${arch}.tar.gz"
  tar -czf "${STUB_DIR}/${archive}" \
    -C "${FIXTURES_DIR}" dractl

  # Compute its real sha256 for checksums.txt
  local sha256
  sha256="$(sha256sum "${STUB_DIR}/${archive}" | awk '{print $1}')"
  echo "${sha256}  ${archive}" >"${STUB_DIR}/checksums.txt"

  # Stub curl: copies files from CURL_STUB_DIR by basename of URL
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
filename="$(basename "${url}")"
cp "${CURL_STUB_DIR}/${filename}" "${output_file}"
EOF
  chmod +x "${STUB_DIR}/curl"
  export CURL_STUB_DIR="${STUB_DIR}"

  # Stub buildkite-agent: records every invocation
  export AGENT_LOG="${STUB_DIR}/buildkite-agent.log"
  cat >"${STUB_DIR}/buildkite-agent" <<'EOF'
#!/usr/bin/env bash
echo "buildkite-agent $*" >> "${AGENT_LOG}"
EOF
  chmod +x "${STUB_DIR}/buildkite-agent"

  # Stub gcloud: records every invocation
  export GCLOUD_LOG="${STUB_DIR}/gcloud.log"
  cat >"${STUB_DIR}/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "gcloud $*" >> "${GCLOUD_LOG}"
EOF
  chmod +x "${STUB_DIR}/gcloud"

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

@test "fails with clear error when artifacts_dir is missing" {
  unset BUILDKITE_PLUGIN_DRA_PREP_ARTIFACTS_DIR
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "artifacts_dir"
}

@test "fails with GithubPermissionSet hint when VAULT_GITHUB_TOKEN is missing" {
  unset VAULT_GITHUB_TOKEN
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "GithubPermissionSet"
}

@test "downloads, verifies, and runs dractl on happy path" {
  # Fake dractl simulates what layout.Create produces:
  # {artifacts_dir}/dra/{product_id}/{build_id}/
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  # Fake dractl wrote build_id = "9.5.0-ab12cd34"
  grep -q "meta-data set DRA_VERSION_BUILD_ID 9.5.0-ab12cd34" "${AGENT_LOG}"
  grep -q "gs://elastic-artifacts-snapshot/dra-builds/apm-server/11/9.5.0-ab12cd34/" "${GCLOUD_LOG}"
}

@test "derives gcs bucket from workflow: staging" {
  export BUILDKITE_PLUGIN_DRA_PREP_WORKFLOW=staging
  run bash "${HOOK}"
  [ "$status" -eq 0 ]
  grep -q "gs://elastic-artifacts-staging/" "${GCLOUD_LOG}"
}

@test "fails when artifacts_dir is absent or empty" {
  rm -rf "${BUILDKITE_PLUGIN_DRA_PREP_ARTIFACTS_DIR}"
  run bash "${HOOK}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "artifacts_dir"
}
