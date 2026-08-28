#!/usr/bin/env bash
# Build a Release copy and install it into /Applications.
#
# Release rather than Debug so the installed app is optimised and drops the
# in-panel debug build tag, but signed against the *-LocalDev entitlements,
# because the full Release entitlements ask for CloudKit, an App Group and push
# — none of which a free Apple Personal Team can provision. That override is
# passed on the command line rather than written into the project, so the
# Release configuration stays honest about what a properly-signed build wants.
set -euo pipefail

cd "$(dirname "$0")/.."

DEST=${DEST:-/Applications}
APP_NAME=SquirrelTrap.app

xcodebuild \
  -project SquirrelTrap.xcodeproj \
  -scheme SquirrelTrap \
  -configuration Release \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_ENTITLEMENTS=SquirrelTrap/SquirrelTrap-LocalDev.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

BUILD_DIR=$(
  xcodebuild -project SquirrelTrap.xcodeproj -scheme SquirrelTrap \
    -configuration Release -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null |
    awk '/ BUILT_PRODUCTS_DIR = /{print $3; exit}'
)
BUILT="$BUILD_DIR/$APP_NAME"

if [ ! -d "$BUILT" ]; then
  echo "Expected a built app at $BUILT but found none." >&2
  exit 1
fi

# Quit every running copy — the DerivedData one from run-local.sh as well as a
# previously installed one — so the replace below can't hit a busy bundle and
# so we don't end up with two menu bar icons and two event taps.
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
  echo "Installed to $DEST/$APP_NAME and running (pid $PID)."
  echo
  echo "macOS scopes Input Monitoring to the app's path, so this copy needs its"
  echo "own grant: System Settings > Privacy & Security > Input Monitoring."
  echo "Remove any older Squirrel Trap entry there, add this one, then quit and"
  echo "relaunch once — the Cmd+Tab event tap only attaches on a fresh launch."
else
  echo "Installed to $DEST/$APP_NAME but it did not stay running." >&2
  exit 1
fi
