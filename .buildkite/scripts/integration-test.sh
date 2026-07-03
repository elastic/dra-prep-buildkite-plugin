#!/usr/bin/env bash
# Creates a minimal artifact set that dractl's classifier recognises.
# The plugin's post-command hook then downloads dractl, runs prep, sets
# DRA_VERSION_BUILD_ID meta-data, and uploads the DRA artifacts.
set -euo pipefail

mkdir -p dra/smoke-test
touch "dra/smoke-test/smoke-test-9.5.0-SNAPSHOT-linux-x86_64.tar.gz"
