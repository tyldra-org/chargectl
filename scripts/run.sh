#!/usr/bin/env bash
# Development loop: Debug build, installed with its service. Same as install.sh --debug.
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/install.sh" --debug "$@"
