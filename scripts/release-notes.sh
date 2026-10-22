#!/usr/bin/env bash
# Prints the GitHub release notes for a version from its CHANGELOG.md section: the summary,
# the changes under release headings, install steps and a link to the full diff.
#
#   ./scripts/release-notes.sh <version>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
changelog="$root/CHANGELOG.md"
repo=https://github.com/tyldra-org/chargectl
if [[ $# -ne 1 ]]; then
  echo 'Usage: release-notes.sh <version>' >&2
  exit 2
fi
version=$1
zip="Chargectl-$version.zip"

# The version's section, with Keep a Changelog's headings renamed for readers.
section=$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { take = 1; next }
  take && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  !take { next }
  /^### Added/      { print "## New features"; next }
  /^### Changed/    { print "## Changes"; next }
  /^### Deprecated/ { print "## Deprecated"; next }
  /^### Removed/    { print "## Removed"; next }
  /^### Fixed/      { print "## Bug fixes"; next }
  /^### Security/   { print "## Security"; next }
  { print }' "$changelog")
if [[ -z "${section//[[:space:]]/}" ]]; then
  echo "release-notes.sh: CHANGELOG.md has no section for $version" >&2
  exit 1
fi
# The compare link at the bottom of CHANGELOG.md; the first release has none.
compare=$(sed -n "s/^\[$version\]: \(.*\/compare\/.*\)$/\1/p" "$changelog")
if [[ -n "$compare" ]]; then
  footer="**Full changelog:** [${compare##*/}]($compare)"
else
  footer="**Full history:** [commits up to v$version]($repo/commits/v$version)"
fi

# GitHub shows every line break in release notes, so wrapped paragraphs and list items are
# joined into single lines. Code blocks and HTML are left as they are.
unwrap() {
  awk '
    function flush() { if (buffer != "") print buffer; buffer = "" }
    /^```/ { flush(); fence = !fence; print; next }
    fence { print; next }
    /^$/ || /^#/ || /^</ { flush(); print; next }
    /^- / { flush(); buffer = $0; next }
    /^  +[^ ]/ && buffer != "" { sub(/^ +/, ""); buffer = buffer " " $0; next }
    buffer != "" { buffer = buffer " " $0; next }
    { buffer = $0 }
    END { flush() }'
}

{
printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
cat <<NOTES

## Install

\`\`\`sh
brew install --cask tyldra-org/tools/chargectl
\`\`\`

Already installed with Homebrew? Run \`brew update && brew upgrade --cask tyldra-org/tools/chargectl\`. To install by hand,
download [\`$zip\`]($repo/releases/download/v$version/$zip), unzip it and move Chargectl to
Applications.

Requires an Apple silicon MacBook on macOS 27 or later.

<details>
<summary>Opening a downloaded copy</summary>

<br>

Chargectl is signed ad hoc and not notarized, so macOS blocks the first launch of a
downloaded copy. Open it once, then choose **Open Anyway** in System Settings › Privacy &
Security. Copies installed with Homebrew open normally.

</details>

<details>
<summary>Verifying the download</summary>

<br>

Each release has a SHA-256 checksum and a build provenance attestation from GitHub
Actions:

\`\`\`sh
shasum -a 256 -c $zip.sha256
gh attestation verify $zip --repo tyldra-org/chargectl
\`\`\`

</details>

$footer
NOTES
} | unwrap
