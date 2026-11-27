#!/usr/bin/env bash
# Measures how much CPU Chargectl and the window server use with the dashboard open on each page,
# in the background and closed. It runs a Debug build with --demo --live-readings: sample data
# whose watts and temperature change every second, as a real Mac's do, and no helper, so it never
# changes how the Mac charges. Run it before a release and after changing the dashboard or the
# menu bar panel.
#
#   scripts/measure-cpu.sh                  builds the Debug app, then measures it
#   scripts/measure-cpu.sh <Chargectl.app>  measures another Debug build, to compare
#
# It never takes the keyboard or moves the mouse: the app stays in the background (--background)
# and its window comes forward without focus. "In front" is measured with --appear-active, which
# draws the dashboard as if Chargectl were the app in front. Keep the window uncovered while it
# runs, about two minutes. CHARGECTL_MEASURE_SECONDS sets how long each state is measured
# (default 15).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

seconds="${CHARGECTL_MEASURE_SECONDS:-15}"
if [[ $# -gt 0 ]]; then
  app="$1"
else
  "$CHARGECTL_ROOT/scripts/build.sh" Debug
  app="$CHARGECTL_DERIVED_DATA/Build/Products/Debug/Chargectl.app"
fi
# The full path without doubled slashes, as the process list shows it.
app="$(cd "$app" 2>/dev/null && pwd -P || true)"
executable="$app/Contents/MacOS/Chargectl"
if [[ ! -x "$executable" ]]; then
  echo "measure-cpu: no Chargectl app at ${1:-the Debug build}" >&2
  exit 2
fi

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# CPU time a process has used so far, in seconds.
cpu_time() { ps -p "$1" -o time= | awk -F: '{ t = 0; for (i = 1; i <= NF; i++) t = t * 60 + $i; print t }'; }
# Average CPU of the app and the window server over the measuring time, as "app% server%".
measure() {
  local app_before server_before start app_after server_after end
  app_before=$(cpu_time "$pid") server_before=$(cpu_time "$server") start=$(now)
  sleep "$seconds"
  app_after=$(cpu_time "$pid") server_after=$(cpu_time "$server") end=$(now)
  awk -v a="$app_before" -v b="$app_after" -v s="$server_before" -v t="$server_after" -v d="$start" -v e="$end" \
    'BEGIN { printf "%.1f%% %.1f%%\n", (b - a) / (e - d) * 100, (t - s) / (e - d) * 100 }'
}
row() { printf '%-26s %10s %14s\n' "$1" "$2" "$3"; }
# Shows a dashboard page. Opening the link with this app, by path, keeps it away from an installed
# Chargectl, which handles chargectl:// links too; -g leaves the app in the background.
show() { open -g -a "$app" "chargectl://dashboard/$1"; }

pid=""
stop() { if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi; }
trap stop EXIT
# start [argument]: runs the app in the background with sample data and sets pid.
start() {
  local arguments=(--demo --live-readings --background "$@")
  open -g -n -a "$app" --args "${arguments[@]}"
  pid=""
  for _ in $(seq 1 20); do
    pid=$(pgrep -f -x "$executable ${arguments[*]}" | head -1 || true)
    [[ -n "$pid" ]] && break
    sleep 0.5
  done
  if [[ -z "$pid" ]]; then
    echo "measure-cpu: Chargectl did not start" >&2
    exit 1
  fi
  sleep 5
}

server=$(pgrep -x WindowServer | head -1)
# The window server's own load, before Chargectl starts. The app's column is this script's shell.
pid=$$
read -r _ idle_server < <(measure)
pid=""

echo "Chargectl $(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString), $seconds s per state"
row "" "Chargectl" "WindowServer"
row "not running" "" "$idle_server"

start --appear-active
for page in overview control history logs settings; do
  show "$page"
  sleep 4
  read -r app_cpu server_cpu < <(measure)
  row "$page, in front" "$app_cpu" "$server_cpu"
done
stop

start
show overview
sleep 4
read -r app_cpu server_cpu < <(measure)
row "overview, in background" "$app_cpu" "$server_cpu"
# Quitting from outside only closes the dashboard; the app stays in the menu bar. AppleScript
# reports that as a cancelled quit.
osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
sleep 4
read -r app_cpu server_cpu < <(measure)
row "window closed" "$app_cpu" "$server_cpu"
row "memory" "$(($(ps -p "$pid" -o rss=) / 1024)) MB" ""
