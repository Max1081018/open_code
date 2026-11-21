#!/usr/bin/env bash
# Runs the test suite and also fails on any script error. A GDScript runtime
# error inside a test aborts that test silently (the call just returns), so
# the runner alone would count it as passed; the error is only in the log.
#   tests/run.sh [name_filter]       (from godot/)
set -o pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
godot --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$log"
status=$?
if grep -q "SCRIPT ERROR" "$log"; then
	echo "FAIL: script errors during the run:" >&2
	grep -A2 "SCRIPT ERROR" "$log" >&2
	status=1
fi
rm -f "$log"
exit $status
