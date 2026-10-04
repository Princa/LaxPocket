#!/usr/bin/env bash
# Regenerates LaxPocket.xcodeproj when project.yml or the list of source files changed, so a pull that adds files
# builds without running xcodegen by hand. Run by the git hooks in .githooks (see scripts/setup-mac.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 0

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "LaxPocket: xcodegen isn't installed, so the Xcode project wasn't updated (brew install xcodegen)." >&2
  exit 0
fi

# --use-cache skips the work when nothing that affects the project changed.
if xcodegen generate --use-cache --quiet; then
  echo "LaxPocket: Xcode project is up to date. If Xcode asks, choose Revert to reload it."
else
  echo "LaxPocket: xcodegen failed; run 'xcodegen generate' to see why." >&2
fi
exit 0
