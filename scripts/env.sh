#!/usr/bin/env bash
# Shared by the build, test and run scripts; source this file.
set -euo pipefail
CHARGECTL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHARGECTL_DERIVED_DATA="${CHARGECTL_DERIVED_DATA:-${TMPDIR:-/tmp}/Chargectl-DerivedData}"
export CHARGECTL_ROOT CHARGECTL_DERIVED_DATA
if [[ "$(xcodebuild -version | awk 'NR == 1 { print $2 }')" != 27.* ]]; then
  echo 'Select Xcode 27 before building Chargectl.' >&2
  exit 1
fi
