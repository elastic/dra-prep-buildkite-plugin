#!/usr/bin/env bash
# Creates a minimal artifact set that dractl's classifier recognises.
# The plugin's post-command hook then downloads dractl, runs prep, and sets
# DRA_VERSION_BUILD_ID meta-data from the generated manifest.
set -euo pipefail

mkdir -p artifacts
touch "artifacts/smoke-test-9.5.0-SNAPSHOT-linux-x86_64.tar.gz"
