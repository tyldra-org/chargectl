#!/usr/bin/env bash
# Runs the checks the Homebrew tap's CI runs on Casks/chargectl.rb, brew style and
# brew audit (as `brew test-bot --only-tap-syntax` does), on the cask scripts/cask.sh
# prints for the current version. CI and the release workflow run it, so a release
# never opens a tap pull request that fails.
#
#   ./scripts/check-cask.sh
#
# It writes the cask to a throwaway tap, chargectl-check/cask, and removes it again.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tap=chargectl-check/cask
taps="$(brew --repository)/Library/Taps"
config=$(mktemp -d)
cleanup() {
  rm -rf "$taps/chargectl-check" "$config"
}
trap cleanup EXIT

# CI checks with the newest Homebrew, as the tap's CI does. Local runs use the
# installed one.
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  brew update --quiet
fi
export HOMEBREW_NO_AUTO_UPDATE=1
# Homebrew loads casks only from trusted taps. Trust the throwaway tap in a private
# trust store, so the user's own is left alone.
export XDG_CONFIG_HOME="$config"

mkdir -p "$taps/chargectl-check/homebrew-cask/Casks"
"$root/scripts/cask.sh" "$("$root/scripts/version.sh")" "$(printf '0%.0s' {1..64})" \
  >"$taps/chargectl-check/homebrew-cask/Casks/chargectl.rb"
brew trust --tap "$tap" >/dev/null
brew style "$tap"
brew audit --except=installed --tap="$tap"
