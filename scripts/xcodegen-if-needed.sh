#!/usr/bin/env bash
# Regenerates LaxPocket.xcodeproj when project.yml changed (or there's no project yet), so a pull that changes the
# project builds without running xcodegen by hand. Adding, renaming or removing source files doesn't need it: the
# app's folder is a synchronized folder, and Xcode picks those up by itself.
#
# Run by the git hooks in .githooks (see scripts/setup-mac.sh), and safe to run any time: when nothing changed it
# leaves the project file alone, so an open Xcode isn't asked to reload it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 0

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "LaxPocket: xcodegen isn't installed, so the Xcode project wasn't updated (brew install xcodegen)." >&2
  exit 0
fi

# XcodeGen rewrites the project even when it comes out the same, so compare what it's generated from instead.
stamp=LaxPocket.xcodeproj/.generated-from
inputs=$({ shasum project.yml; xcodegen --version; } | shasum | cut -d' ' -f1)
if [ -f LaxPocket.xcodeproj/project.pbxproj ] && [ -f LaxPocket/Info.plist ] && [ "$(cat "$stamp" 2>/dev/null)" = "$inputs" ]; then
  exit 0
fi

if xcodegen generate --quiet; then
  echo "$inputs" > "$stamp"
  echo "LaxPocket: regenerated the Xcode project (project.yml changed). If Xcode asks, choose Revert to reload it."
else
  echo "LaxPocket: xcodegen failed; run 'xcodegen generate' to see why." >&2
fi
exit 0
