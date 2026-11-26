#!/usr/bin/env bash
# Creates a minimal artifact set that dractl's classifier recognises.
# The plugin's post-command hook then downloads dractl, runs prep, and sets
# DRA_VERSION_BUILD_ID meta-data from the generated manifest.
set -euo pipefail

# Keep the live credential out of shell traces. The proof below records only
# GitHub's HTTP status codes and discards both response bodies.
set +x

mkdir -p artifacts
touch "artifacts/smoke-test-9.5.0-SNAPSHOT-linux-x86_64.tar.gz"

release_url="https://api.github.com/repos/elastic/dractl/releases/tags/v0.1.11"
curl_args=(
  --silent
  --show-error
  --output /dev/null
  --write-out "%{http_code}"
  --connect-timeout 10
  --max-time 30
  --header "Accept: application/vnd.github+json"
  --header "X-GitHub-Api-Version: 2022-11-28"
)

control_status="$(curl "${curl_args[@]}" "${release_url}")"
authenticated_status="$(curl "${curl_args[@]}" \
  --header "Authorization: Bearer ${VAULT_GITHUB_TOKEN:-}" \
  "${release_url}")"

printf 'control_status=%s\n' "${control_status}"
printf 'authenticated_status=%s\n' "${authenticated_status}"

[[ "${control_status}" == "404" ]]
[[ "${authenticated_status}" == "200" ]]
