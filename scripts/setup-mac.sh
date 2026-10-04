#!/usr/bin/env bash
# One-time setup on your Mac. After this, `git pull` (or Claude Code pulling or switching branches) regenerates the
# Xcode project on its own, and the project always has your signing team, so you just build.
#
#   scripts/setup-mac.sh              # finds your team from your Apple Development certificate
#   scripts/setup-mac.sh ABCDE12345   # or give the team ID
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen…"
    brew install xcodegen
  else
    echo "Install XcodeGen first: brew install xcodegen (https://brew.sh)" >&2
    exit 1
  fi
fi

# 1. Regenerate the project automatically after pulls, checkouts and rebases.
chmod +x .githooks/* scripts/xcodegen-if-needed.sh
git config core.hooksPath .githooks
echo "✓ Git hooks on: the Xcode project updates itself after a pull."

# 2. Remember the signing team.
team="${1:-}"
if [ -z "$team" ] && [ -f Config/Local.xcconfig ]; then
  team=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig | head -1)
fi
if [ -z "$team" ]; then
  # The team ID is the OU of the Apple Development certificate Xcode installed.
  team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
fi
if [ -z "$team" ]; then
  read -r -p "Apple developer team ID (Xcode → Settings → Accounts): " team
fi
if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "That doesn't look like a team ID (10 letters and digits). Run again with it: scripts/setup-mac.sh ABCDE12345" >&2
  exit 1
fi
printf '// Your signing team, for local builds. Not committed.\nDEVELOPMENT_TEAM = %s\n' "$team" > Config/Local.xcconfig
echo "✓ Signing team $team saved in Config/Local.xcconfig (not committed)."

# 3. Generate the project now.
xcodegen generate --quiet
echo "✓ LaxPocket.xcodeproj generated. Open it, pick your iPhone and press Run."
