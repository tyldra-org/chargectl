#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: build.sh [Debug|Release]' >&2; exit 2 ;; esac
"$CHARGECTL_ROOT/scripts/generate.sh"
exec xcodebuild -quiet -project "$CHARGECTL_ROOT/Chargectl.xcodeproj" -scheme Chargectl \
  -configuration "$configuration" -destination 'generic/platform=macOS' \
  -derivedDataPath "$CHARGECTL_DERIVED_DATA" build
