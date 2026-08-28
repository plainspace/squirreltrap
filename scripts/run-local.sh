#!/usr/bin/env bash
# Build and install to /Applications, then relaunch.
#
# It installs rather than running out of DerivedData on purpose. macOS scopes
# Input Monitoring to the app's PATH, so a DerivedData build and an installed
# build are two different apps as far as TCC is concerned, and alternating
# between them means re-granting permission every single time. Everything runs
# from one path so the grant is given once and then holds.
#
# Squirrel Trap is a menu-bar agent with no Dock icon, so "did it start?" is not
# obvious: the script reports the PID at the end rather than leaving you to
# guess. It also kills any running copy first, because the CGEventTap that
# watches for Cmd+Tab only reliably starts delivering events on a fresh process
# launch, never mid-session.
#
# CONFIGURATION=Release ./scripts/run-local.sh builds the shipping variant to
# the same path. install-local.sh is a thin wrapper that does exactly that.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION=${CONFIGURATION:-Debug}
DEST=${DEST:-/Applications}
APP_NAME=SquirrelTrap.app

# Release's own entitlements ask for CloudKit, an App Group and push, none of
# which a free Apple Personal Team can provision. Signing both configurations
# against the LocalDev set keeps the installed path buildable either way, and
# keeps the code signature's designated requirement identical between them,
# which is what lets one TCC grant cover both.
xcodebuild \
  -project SquirrelTrap.xcodeproj \
  -scheme SquirrelTrap \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_ENTITLEMENTS=SquirrelTrap/SquirrelTrap-LocalDev.entitlements \
  build

# Ask xcodebuild where it actually put the product rather than hardcoding a
# DerivedData path, which contains a per-checkout hash.
BUILD_DIR=$(
  xcodebuild -project SquirrelTrap.xcodeproj -scheme SquirrelTrap \
    -configuration "$CONFIGURATION" -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null |
    awk '/ BUILT_PRODUCTS_DIR = /{print $3; exit}'
)
BUILT="$BUILD_DIR/$APP_NAME"

if [ ! -d "$BUILT" ]; then
  echo "Expected a built app at $BUILT but found none." >&2
  exit 1
fi

pkill -x SquirrelTrap 2>/dev/null || true
# Wait for it to actually be gone, both so the copy below can't hit a bundle
# that's still mapped and so the subsequent open doesn't race LaunchServices
# into error -600.
for _ in $(seq 1 40); do
  pgrep -x SquirrelTrap >/dev/null || break
  sleep 0.1
done

if [ ! -w "$DEST" ]; then
  echo "$DEST is not writable. Re-run with DEST=\"\$HOME/Applications\"." >&2
  exit 1
fi

rm -rf "${DEST:?}/$APP_NAME"
cp -R "$BUILT" "$DEST/$APP_NAME"
open "$DEST/$APP_NAME"

sleep 1
if PID=$(pgrep -x SquirrelTrap); then
  echo "$CONFIGURATION build installed to $DEST/$APP_NAME and running (pid $PID)."
else
  echo "Installed to $DEST/$APP_NAME but it did not stay running." >&2
  exit 1
fi
