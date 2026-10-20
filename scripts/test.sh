#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
"$CHARGECTL_ROOT/scripts/generate.sh"
exec xcodebuild -quiet -project "$CHARGECTL_ROOT/Chargectl.xcodeproj" -scheme Chargectl \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$CHARGECTL_DERIVED_DATA" test
