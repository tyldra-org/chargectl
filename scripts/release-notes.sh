#!/usr/bin/env bash
# Prints the release notes for a version: its CHANGELOG.md section, then install steps.
#
#   ./scripts/release-notes.sh <version>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 1 ]]; then
  echo 'Usage: release-notes.sh <version>' >&2
  exit 2
fi
version=$1
notes=$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { take = 1; next }
  take && /^## \[/ { exit }
  take && /^\[[^]]+\]: / { exit }
  take { print }' "$root/CHANGELOG.md")
if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "release-notes.sh: CHANGELOG.md has no section for $version" >&2
  exit 1
fi
printf '%s\n' "$notes" | sed -e '/./,$!d'
cat <<NOTES

## Install

\`\`\`sh
brew install --cask tyldra-org/tools/chargectl
\`\`\`

Or download \`Chargectl-$version.zip\`, unzip it and move Chargectl to Applications. The app
is not notarized, so macOS blocks the first launch of a downloaded copy: open it, then
choose **Open Anyway** in System Settings › Privacy & Security. Homebrew installs skip this
step.

Check the download:

\`\`\`sh
shasum -a 256 -c Chargectl-$version.zip.sha256
gh attestation verify Chargectl-$version.zip --repo tyldra-org/chargectl
\`\`\`
NOTES
