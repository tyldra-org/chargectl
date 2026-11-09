#!/usr/bin/env bash
# Runs the ChargectlTests suites.
#
#   CHARGECTL_TEST_SUITES   unset, empty or "all": every suite. "none": build the tests
#                           without running them. Otherwise the suites to run, by name
#                           (ChargePolicyTests ChargeControllerTests); CI sets it from
#                           scripts/ci-scope.sh so a pull request runs only what it reaches.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
"$CHARGECTL_ROOT/scripts/generate.sh"
suites=${CHARGECTL_TEST_SUITES:-all}
action='test'
only=()
case $suites in
  all) ;;
  none)
    echo 'test.sh: no test suite reaches this change; building the tests without running them.'
    action=build-for-testing
    ;;
  *)
    for suite in $suites; do
      [[ $suite =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "test.sh: bad suite name: $suite" >&2; exit 2; }
      only+=("-only-testing:ChargectlTests/$suite")
    done
    echo "test.sh: running $suites"
    ;;
esac
exec xcodebuild -quiet -project "$CHARGECTL_ROOT/Chargectl.xcodeproj" -scheme Chargectl \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$CHARGECTL_DERIVED_DATA" ${only[@]+"${only[@]}"} "$action"
