#!/usr/bin/env bash
# Runs the golden-file synthesis tests under a headless Godot.
#
# Usage:
#   tests/run.sh                 # run tests; exit 0 pass, 1 fail
#   tests/run.sh -- --generate   # (re)write tests/golden.json
#   GODOT=/path/to/godot tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${GODOT:-godot}" --headless --path . --script res://tests/run_tests.gd "$@"
