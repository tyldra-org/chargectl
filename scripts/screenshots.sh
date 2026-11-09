#!/usr/bin/env bash
# Takes the README's screenshots of the running app: every dashboard page and the first
# setup step, in dark and light. It runs a Debug build with sample data (--demo), which
# never talks to the helper, so charging is not affected.
#
#   ./scripts/screenshots.sh [Chargectl.app] [folder]
#
# The app defaults to the Debug build from `./scripts/build.sh Debug`, the folder to
# docs/assets/screenshots. Windows open on the sharpest screen, so a Retina display gives
# 2x images. The terminal needs the Screen Recording permission. The menu bar panel and
# the widgets are not covered here; see CONTRIBUTING.md.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app=${1:-"${CHARGECTL_DERIVED_DATA:-${TMPDIR:-/tmp}/Chargectl-DerivedData}/Build/Products/Debug/Chargectl.app"}
out=${2:-"$root/docs/assets/screenshots"}
binary="$app/Contents/MacOS/Chargectl"
pages=(overview control history logs settings)

[[ -x "$binary" ]] || { echo "screenshots.sh: no Debug build at $app; run ./scripts/build.sh Debug" >&2; exit 1; }
# chargectl:// links go to the running copy of this app; a second one would take them.
if pgrep -f "$binary" >/dev/null; then
  echo "screenshots.sh: $app is already running; quit it first (in Xcode: Stop)." >&2
  exit 1
fi
mkdir -p "$out"

# window_id <pid> <title>: the number of that process's on-screen window with this title.
window_id() {
  local id=''
  for _ in $(seq 1 40); do
    id=$(swift -e "
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerPID as String] as? Int) == $1
  && (w[kCGWindowLayer as String] as? Int) == 0 && (w[kCGWindowName as String] as? String) == \"$2\" {
  print(w[kCGWindowNumber as String]!)
  break
}")
    [[ -n "$id" ]] && break
    sleep 0.5
  done
  [[ -n "$id" ]] || { echo "screenshots.sh: no window \"$2\"" >&2; return 1; }
  echo "$id"
}

pid=''
trap '[[ -n "$pid" ]] && kill "$pid" 2>/dev/null; true' EXIT
for mode in dark light; do
  # -appearance and -setupComplete set preferences for this run only (the arguments
  # domain); setup then starts at its first step.
  "$binary" --demo --screenshots -appearance "$mode" -setupComplete NO >/dev/null 2>&1 &
  pid=$!
  sleep 3
  open -a "$app" chargectl://dashboard/overview
  id=$(window_id "$pid" Chargectl)
  for page in "${pages[@]}"; do
    open -a "$app" "chargectl://dashboard/$page"
    sleep 3 # pages settle in, and numbers roll to their values
    screencapture -x -l "$id" "$out/$page-$mode.png"
    echo "$out/$page-$mode.png"
  done
  open -a "$app" chargectl://welcome
  id=$(window_id "$pid" "Welcome to Chargectl")
  sleep 3 # the first step's ring charges up
  screencapture -x -l "$id" "$out/setup-$mode.png"
  echo "$out/setup-$mode.png"
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  pid=''
done

# Smaller files for the repository: 1800 pixels wide is 2x the README's widest picture.
for mode in dark light; do
  for page in "${pages[@]}"; do
    sips --resampleWidth 1800 "$out/$page-$mode.png" >/dev/null
  done
  sips --resampleWidth 1100 "$out/setup-$mode.png" >/dev/null
done
# And smaller again when pngquant is installed (brew install pngquant).
if command -v pngquant >/dev/null; then
  for mode in dark light; do
    for name in "${pages[@]}" setup; do
      pngquant --quality 88-100 --skip-if-larger --strip --force --ext .png "$out/$name-$mode.png" || true
    done
  done
fi
