#!/usr/bin/env bash
# Usage: scripts/ci-run.sh "<title>" <log file> <command...>
#
# Runs a CI command, keeps its full output in <log file>, and when it fails
# turns the error lines into a single GitHub annotation, so the failure
# reason shows on the run summary (and through the checks API) without
# downloading the raw log.
set -uo pipefail

title="$1"
log="$2"
shift 2

"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  lines=$(grep -E -A3 "error:|error :|: failed|fatal error|\*\* BUILD FAILED|Test Case .* failed" "$log" \
    | grep -v -E "^--$" | awk '!seen[$0]++' | head -160)
  [ -z "$lines" ] && lines=$(tail -80 "$log")
  msg=$(printf '%s\n' "$lines" | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN { ORS = "%0A" } { print }')
  echo "::error title=${title}::${msg}"
fi

exit "$status"
