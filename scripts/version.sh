#!/usr/bin/env bash
# Prints Chargectl's version, MARKETING_VERSION in project.yml.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=$(sed -n "s/^ *MARKETING_VERSION: '\([^']*\)'$/\1/p" "$root/project.yml")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version.sh: MARKETING_VERSION in project.yml is not MAJOR.MINOR.PATCH: '$version'" >&2
  exit 1
fi
echo "$version"
