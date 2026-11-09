#!/usr/bin/env bash
# Decides what CI has to check for a change, from the files it touches.
#
#   scripts/ci-scope.sh areas <base> [head]   the jobs it needs, as GITHUB_OUTPUT lines:
#                                             full, swift, cask, shell and workflows
#   scripts/ci-scope.sh tests <base> [head]   the test suites it reaches, as one line:
#                                             tests=all, tests=none or tests=<Suite> ...
#
# Without [head], the working tree is compared, new files included. An empty,
# all-zero or unknown <base> means "check everything". The classify and suites
# modes take paths instead of commits; scripts/ci-scope.test.sh uses them.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
}

# The CI wiring itself: every check runs.
is_full() {
  case $1 in .github/workflows/ci.yml | scripts/ci-scope.sh | scripts/check.sh) return 0 ;; esac
  return 1
}
# Swift sources, app resources and what builds them: format, build and test on macOS.
is_swift() {
  case $1 in
    *.swift | project.yml | .swift-format | App/* | Daemon/* | Shared/* | Widgets/* | Tests/*) return 0 ;;
    scripts/build.sh | scripts/test.sh | scripts/generate.sh | scripts/env.sh) return 0 ;;
  esac
  return 1
}
# What the Homebrew cask is made from: brew style and audit.
is_cask() {
  case $1 in scripts/cask.sh | scripts/check-cask.sh | scripts/version.sh | project.yml) return 0 ;; esac
  return 1
}
is_shell() {
  case $1 in *.sh | *.bash) return 0 ;; esac
  return 1
}
is_workflow() {
  case $1 in .github/workflows/* | .github/actionlint.yaml) return 0 ;; esac
  return 1
}
# Changes every test depends on: the project, the test target's build and test helpers.
is_test_global() {
  case $1 in project.yml | .swift-format | scripts/test.sh | scripts/generate.sh | scripts/env.sh) return 0 ;; esac
  return 1
}

classify() {
  local full=false swift=false cask=false shell=false workflows=false file
  for file in "$@"; do
    if is_full "$file"; then full=true; fi
    if is_swift "$file"; then swift=true; fi
    if is_cask "$file"; then cask=true; fi
    if is_shell "$file"; then shell=true; fi
    if is_workflow "$file"; then workflows=true; fi
  done
  if [ "$full" = true ]; then swift=true cask=true shell=true workflows=true; fi
  printf 'full=%s\nswift=%s\ncask=%s\nshell=%s\nworkflows=%s\n' "$full" "$swift" "$cask" "$shell" "$workflows"
}

# suite_of <test file>: the @Suite type it declares, or nothing for a helper file.
suite_of() {
  sed -n -E 's/^@Suite.*struct ([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$1" | head -1
}

# The test target builds Tests, Shared and Daemon (project.yml), so only changes there
# can change what a test does.
TESTED='Shared Daemon'

# known_types: every struct, enum, class, actor and protocol the test target declares.
known_types() {
  # shellcheck disable=SC2086 # TESTED is a fixed list of directories.
  grep -rhoE '(struct|enum|class|actor|protocol)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' $TESTED --include='*.swift' |
    awk '{ print $2 }' | sort -u
}

# declared <swift file> <known types>: the names a change to the file can affect, one
# per line: the types it declares, the known types it extends, and its own name.
declared() {
  sed -n -E 's/^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*((public|internal|private|fileprivate|package|final|nonisolated|open|indirect)[[:space:]]+)*(struct|enum|class|actor|protocol)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\5/p' "$1"
  sed -n -E 's/^[[:space:]]*((public|internal|private|fileprivate|package|nonisolated)[[:space:]]+)*extension[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p' "$1" |
    grep -Fx -f <(printf '%s\n' "$2") || true
  basename "$1" .swift
}

# reached <file>...: the names reached from the given Shared and Daemon files: what they
# declare, then what every file using those names declares, until nothing new turns up.
reached() {
  local known names visited new file
  known=$(known_types)
  names=$(for file in "$@"; do declared "$file" "$known"; done | sort -u)
  visited=$(printf '%s\n' "$@")
  while :; do
    new=''
    # shellcheck disable=SC2086 # TESTED is a fixed list of directories.
    while IFS= read -r file; do
      if [ -n "$file" ] && ! printf '%s\n' "$visited" | grep -Fxq "$file"; then
        visited=$(printf '%s\n%s' "$visited" "$file")
        new=$(printf '%s\n%s' "$new" "$(declared "$file" "$known")")
      fi
    done < <(grep -rlwE "$(printf '%s\n' "$names" | paste -sd '|' -)" $TESTED --include='*.swift')
    if [ -z "$new" ]; then break; fi
    names=$(printf '%s\n%s\n' "$names" "$new" | sed '/^$/d' | sort -u)
  done
  printf '%s\n' "$names"
}

# suites <path>...: "all", "none", or the test suites the paths reach. A test file
# reaches its own suite. A Shared or Daemon file reaches every suite that names a type
# it declares or extends, directly or through other files that use it. App and Widgets
# are not in the test target, so they reach none.
suites() {
  local picked='' sources=() file test name pattern
  for file in "$@"; do
    if is_full "$file" || is_test_global "$file"; then
      echo all
      return
    fi
    case $file in
      Tests/*.swift)
        # A deleted file, or a helper shared by several suites: run them all.
        name=''
        if [ -f "$file" ]; then name=$(suite_of "$file"); fi
        if [ -z "$name" ]; then
          echo all
          return
        fi
        picked="$picked $name"
        ;;
      # The helper's entry point is left out of the test target.
      Daemon/main.swift) ;;
      Shared/*.swift | Daemon/*.swift)
        if [ ! -f "$file" ]; then
          echo all
          return
        fi
        sources+=("$file")
        ;;
    esac
  done
  if [ ${#sources[@]} -gt 0 ]; then
    pattern=$(reached "${sources[@]}" | paste -sd '|' -)
    for test in Tests/*.swift; do
      if grep -qwE "$pattern" "$test"; then
        name=$(suite_of "$test")
        if [ -z "$name" ]; then
          echo all
          return
        fi
        picked="$picked $name"
      fi
    done
  fi
  if [ -z "$picked" ]; then
    echo none
  else
    # shellcheck disable=SC2086 # Split the list of suite names, one per line.
    printf '%s\n' $picked | sort -u | paste -sd ' ' -
  fi
}

# changed <base> [head]: the files that differ, or a failure when the diff is unknown.
changed() {
  if [ -n "$2" ]; then
    git diff --name-only --no-renames "$1" "$2" 2>/dev/null
  else
    git diff --name-only --no-renames "$1" 2>/dev/null && git ls-files --others --exclude-standard
  fi
}

mode=${1:-}
if [ $# -gt 0 ]; then shift; fi
case $mode in
  areas | tests)
    base=${1:-}
    head=${2:-}
    files=()
    if [[ -n $base && ! $base =~ ^0+$ ]] && list=$(changed "$base" "$head"); then
      while IFS= read -r file; do
        if [ -n "$file" ]; then files+=("$file"); fi
      done <<<"$list"
      echo "ci-scope: ${#files[@]} changed file(s) since ${base:0:12}" >&2
      if [ "$mode" = areas ]; then
        classify ${files[@]+"${files[@]}"}
      else
        echo "tests=$(suites ${files[@]+"${files[@]}"})"
      fi
    else
      echo 'ci-scope: the diff is unknown, so everything is checked' >&2
      if [ "$mode" = areas ]; then classify .github/workflows/ci.yml; else echo tests=all; fi
    fi
    ;;
  classify) classify "$@" ;;
  suites) echo "tests=$(suites "$@")" ;;
  *)
    usage
    exit 2
    ;;
esac
