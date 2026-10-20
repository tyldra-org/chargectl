#!/usr/bin/env bash
# Single quality entry point for Chargectl. Developers and CI run the
# same stages, so a green local run predicts a green CI run.
#
# Usage: scripts/check.sh [--all] [--list] [stage...]
#
#   stage            Run only the named stages. Default: every stage.
#   --all            Strict mode for CI and releases: a missing tool or an
#                    unconfigured command fails the stage instead of skipping.
#   --list           Print the stages and their commands, then exit.
#   -h, --help       Show this help.
#
# Stages: format lint build test shell workflows.
# Override a stage command with CHECK_<STAGE>_CMD, for example
# CHECK_TEST_CMD='cargo test --locked'. Set it to an empty string to disable a
# stage that does not apply to this project.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

FORMAT_CMD=${CHECK_FORMAT_CMD-'xcrun swift-format lint --strict --recursive App Daemon Shared Tests'}
# swift-format lint runs in the format stage; there is no separate linter.
LINT_CMD=${CHECK_LINT_CMD-''}
BUILD_CMD=${CHECK_BUILD_CMD-'scripts/build.sh Release'}
TEST_CMD=${CHECK_TEST_CMD-'scripts/test.sh'}

ALL_STAGES="format lint build test shell workflows"

strict=false
stages=()
results=()
failed=0

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

die() {
  printf 'check.sh: %s\n' "$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --all) strict=true ;;
    --list) list_only=true ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *)
      case " $ALL_STAGES " in
        *" $1 "*) stages+=("$1") ;;
        *) die "unknown stage: $1 (stages: $ALL_STAGES)" ;;
      esac
      ;;
  esac
  shift
done

if [ ${#stages[@]} -eq 0 ]; then
  # shellcheck disable=SC2206 # Intentional word splitting of a fixed list.
  stages=($ALL_STAGES)
fi

stage_command() {
  case $1 in
    format) printf '%s' "$FORMAT_CMD" ;;
    lint) printf '%s' "$LINT_CMD" ;;
    build) printf '%s' "$BUILD_CMD" ;;
    test) printf '%s' "$TEST_CMD" ;;
    shell) printf '%s' 'shellcheck <tracked *.sh files>' ;;
    workflows) printf '%s' 'actionlint' ;;
  esac
}

if [ "${list_only:-false}" = true ]; then
  for s in $ALL_STAGES; do
    printf '%-10s %s\n' "$s" "$(stage_command "$s")"
  done
  exit 0
fi

group_start() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    printf '::group::%s\n' "$1"
  else
    printf '\n==> %s\n' "$1"
  fi
}

group_end() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then printf '::endgroup::\n'; fi
}

record() {
  # record <stage> <status> [detail]
  results+=("$(printf '%-10s %-7s %s' "$1" "$2" "${3:-}")")
  if [ "$2" = FAIL ]; then failed=$((failed + 1)); fi
}

skip_or_fail() {
  # A skip is visible and named; under --all it is a failure.
  if [ "$strict" = true ]; then
    record "$1" FAIL "$2 (required by --all)"
    printf 'error: %s: %s\n' "$1" "$2" >&2
  else
    record "$1" skip "$2"
    printf 'skip: %s: %s\n' "$1" "$2"
  fi
}

run_timed() {
  # run_timed <stage> <display label> <command...>
  local stage=$1 label=$2 start=$SECONDS rc=0
  shift 2
  group_start "$stage: $label"
  "$@" || rc=$?
  group_end
  if [ "$rc" -eq 0 ]; then
    record "$stage" ok "$((SECONDS - start))s"
  else
    record "$stage" FAIL "exit status $rc after $((SECONDS - start))s"
  fi
}

run_command_stage() {
  local stage=$1 cmd tool
  cmd=$(stage_command "$stage")
  if [ -z "$cmd" ]; then
    record "$stage" off "disabled by empty CHECK_$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')_CMD"
    return
  fi
  case $cmd in
    *'{{'*) skip_or_fail "$stage" "command not configured: $cmd"; return ;;
  esac
  read -r tool _ <<<"$cmd"
  if ! command -v "$tool" >/dev/null 2>&1; then
    skip_or_fail "$stage" "missing tool: $tool"
    return
  fi
  run_timed "$stage" "$cmd" bash -c "set -euo pipefail; $cmd"
}

shell_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -- '*.sh' '*.bash'
  else
    find . -path ./node_modules -prune -o -type f \( -name '*.sh' -o -name '*.bash' \) -print
  fi
}

run_shell_stage() {
  local files=()
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(shell_files)
  if [ ${#files[@]} -eq 0 ]; then
    record shell ok "no shell scripts"
    return
  fi
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip_or_fail shell "missing tool: shellcheck"
    return
  fi
  run_timed shell "shellcheck (${#files[@]} files)" shellcheck --severity=warning "${files[@]}"
}

run_workflows_stage() {
  if [ ! -d .github/workflows ]; then
    record workflows ok "no workflows"
    return
  fi
  if ! command -v actionlint >/dev/null 2>&1; then
    skip_or_fail workflows "missing tool: actionlint"
    return
  fi
  run_timed workflows actionlint actionlint
}

for stage in "${stages[@]}"; do
  case $stage in
    format | lint | build | test) run_command_stage "$stage" ;;
    shell) run_shell_stage ;;
    workflows) run_workflows_stage ;;
  esac
done

printf '\nSummary%s\n' "$([ "$strict" = true ] && printf ' (--all)')"
for line in "${results[@]}"; do
  printf '  %s\n' "$line"
done

if [ "$failed" -gt 0 ]; then
  printf '\n%d stage(s) failed.\n' "$failed" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
