#!/usr/bin/env bash
# Tests for scripts/ci-scope.sh: which CI jobs and test suites a change needs. Run by
# the workflows stage of scripts/check.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
failed=0
passed=0

# expect <expected output> <ci-scope.sh arguments>...
expect() {
  local expected=$1 actual
  shift
  actual=$(scripts/ci-scope.sh "$@" 2>/dev/null | paste -sd ' ' -)
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
  else
    printf 'FAIL: ci-scope.sh %s\n  expected: %s\n  actual:   %s\n' "$*" "$expected" "$actual" >&2
    failed=$((failed + 1))
  fi
}

# includes <suite> <ci-scope.sh suites arguments>...: the suite is among those picked.
includes() {
  local suite=$1 actual
  shift
  actual=$(scripts/ci-scope.sh suites "$@")
  case " ${actual#tests=} " in
    *" $suite "*) passed=$((passed + 1)) ;;
    *)
      printf 'FAIL: ci-scope.sh suites %s\n  expected to include: %s\n  actual: %s\n' "$*" "$suite" "$actual" >&2
      failed=$((failed + 1))
      ;;
  esac
}

areas() { printf 'full=%s swift=%s cask=%s shell=%s workflows=%s' "$@"; }
nothing=$(areas false false false false false)
everything=$(areas true true true true true)

# Which jobs a change needs.
expect "$nothing" classify README.md CHANGELOG.md docs/assets/icon.png LICENSE
expect "$nothing" classify .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/bug_report.yml
expect "$nothing" classify .github/dependabot.yml .gitignore docs/assets/screenshots/overview.png
expect "$(areas false true false false false)" classify App/Dashboard/OverviewPage.swift
expect "$(areas false true false false false)" classify App/Resources/AppIcon.icon/icon.json Daemon/Resources/Info.plist
expect "$(areas false true true false false)" classify project.yml
expect "$(areas false false true true false)" classify scripts/cask.sh
expect "$(areas false true false true false)" classify scripts/test.sh
expect "$(areas false false false true false)" classify scripts/screenshots.sh
expect "$(areas false false false false true)" classify .github/workflows/release.yml
expect "$everything" classify .github/workflows/ci.yml
expect "$everything" classify scripts/check.sh README.md
expect "$everything" classify scripts/ci-scope.sh
# A path no list names checks everything, never nothing.
expect "$everything" classify .editorconfig
expect "$everything" classify README.md Assets/new-thing.json
# An unknown diff checks everything.
expect "$everything" areas ''
expect "$everything" areas 0000000000000000000000000000000000000000
expect 'tests=all' tests ''
# No changes, nothing to check.
expect "$nothing" areas HEAD HEAD
expect 'tests=none' tests HEAD HEAD

# Which test suites a change reaches.
expect 'tests=ChargePolicyTests' suites Tests/ChargePolicyTests.swift
expect 'tests=AppReleaseTests ChargePolicyTests' suites Tests/ChargePolicyTests.swift Tests/AppReleaseTests.swift
expect 'tests=all' suites project.yml
expect 'tests=all' suites scripts/test.sh
expect 'tests=all' suites Tests/Deleted.swift
expect 'tests=all' suites Shared/Deleted.swift
expect 'tests=none' suites README.md scripts/cask.sh
expect 'tests=all' suites Assets/new-thing.json
# App and Widgets are not in the test target.
expect 'tests=none' suites App/Updater.swift Widgets/Views/WidgetViews.swift Daemon/main.swift
includes AppReleaseTests Shared/Update/AppRelease.swift
# DaemonIdentity compares helper versions with AppRelease, so its tests run too.
includes FeatureTests Shared/Update/AppRelease.swift
includes ChargePolicyTests Shared/Control/ChargePolicy.swift
# The controller runs the policy, so a policy change reaches the controller's tests.
includes ChargeControllerTests Shared/Control/ChargePolicy.swift
includes ChargeControllerTests Daemon/ChargeController.swift

echo "ci-scope.test.sh: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
