#!/bin/zsh
# Builds LockApps.app into ./build with swiftc directly (works with Command Line Tools only, no Xcode).
#   ./build.sh            # release build (+ install to ~/Applications)
#   ./build.sh debug      # debug build (build/LockApps.app only)
#   ./build.sh --run      # build, then (re)launch the app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
RUN=0
for arg in "$@"; do
  case "$arg" in
    debug) CONFIG=debug ;;
    --run) RUN=1 ;;
  esac
done

APP_NAME=LockApps
VERSION=$(sed -n 's/^version: *//p' VERSION 2>/dev/null || echo 0.1.0)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

OPT=(-O -wmo -Xlinker -dead_strip)
[[ "$CONFIG" == "debug" ]] && OPT=(-Onone -g)
mkdir -p build

# Work around a broken Command Line Tools install where a stale
# usr/include/swift/module.modulemap redefines 'SwiftBridging' (see Scripts/toolchain-fix).
EXTRA=()
CLT_INC=/Library/Developer/CommandLineTools/usr/include/swift
if [[ -f "$CLT_INC/module.modulemap" && -f "$CLT_INC/bridging.modulemap" ]]; then
  FIX_DIR="$(pwd)/Scripts/toolchain-fix"
  sed "s|__FIX_DIR__|$FIX_DIR|" "$FIX_DIR/overlay.yaml.in" > build/overlay.yaml
  EXTRA+=(-vfsoverlay build/overlay.yaml)
  echo "▶ applying toolchain-fix VFS overlay"
fi
EXTRA+=(-module-cache-path build/ModuleCache)

echo "▶ swiftc ($CONFIG, $ARCH)"
swiftc "${OPT[@]}" -parse-as-library -swift-version 5 \
  -target "${ARCH}-apple-macos14.0" -sdk "$SDK" "${EXTRA[@]}" \
  $(find Sources/LockApps -name '*.swift' | sort) \
  -o "build/$APP_NAME"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
BUNDLE_ID=com.geonhee.lockapps
[[ "$CONFIG" == "debug" ]] && BUNDLE_ID=com.geonhee.lockapps.dev   # keep the dev copy distinct for LaunchServices
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" -e "s/<string>com.geonhee.lockapps<\/string>/<string>$BUNDLE_ID<\/string>/" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns || Scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  echo "▶ generating app icon"
  swiftc -O -target "${ARCH}-apple-macos14.0" -sdk "$SDK" "${EXTRA[@]}" Scripts/make-icon.swift -o build/make-icon
  ./build/make-icon build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Background agent definition for SMAppService (RunAtLoad + relaunch on crash/kill).
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp Resources/com.geonhee.lockapps.agent.plist "$APP/Contents/Library/LaunchAgents/com.geonhee.lockapps.agent.plist"

# Finder stamps com.apple.FinderInfo on launched bundles and codesign refuses to seal a bundle carrying it.
xattr -cr "$APP" 2>/dev/null || true
# A stable signing identity keeps the login item / permissions tied to the same app across rebuilds;
# ad-hoc signatures change every build.
SIGN_IDENTITY="${LOCKAPPS_SIGN_IDENTITY:-Omni Dev Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  SIGN_WITH="$SIGN_IDENTITY"
else
  SIGN_WITH="-"
fi
signed=0
for attempt in 1 2 3; do
  xattr -cr "$APP" 2>/dev/null || true
  if codesign --force --sign "$SIGN_WITH" "$APP" 2>/dev/null; then signed=1; break; fi
  sleep 0.3
done
if [[ $signed -ne 1 ]] || ! codesign --verify "$APP" 2>/dev/null; then
  echo "✖ codesign did not produce a valid signature:"
  codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/   /'
  exit 1
fi
echo "✔ built $APP"

# Release builds go to ~/Applications so the login item points at a stable copy;
# build/LockApps.app stays for development and screenshots.
INSTALL_APP="${LOCKAPPS_INSTALL_DIR:-$HOME/Applications}/$APP_NAME.app"
if [[ "$CONFIG" != "debug" ]]; then
  mkdir -p "$(dirname "$INSTALL_APP")"
  rm -rf "$INSTALL_APP"
  ditto --noextattr --noqtn "$APP" "$INSTALL_APP"
  codesign --verify "$INSTALL_APP" && echo "✔ installed $INSTALL_APP"
  # Only the installed copy may answer to the bundle identifier: smd derives the agent's launch constraint from
  # whatever LaunchServices resolves for it, and a stale build/ copy makes every spawn a constraint violation.
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
  "$LSREG" -f "$INSTALL_APP" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    RESOLVED="$(osascript -e 'POSIX path of (path to application id "com.geonhee.lockapps")' 2>/dev/null | sed 's:/$::')"
    [[ "$RESOLVED" == "$INSTALL_APP" ]] && break
    sleep 1; "$LSREG" -f "$INSTALL_APP" >/dev/null 2>&1 || true
  done
  [[ "$RESOLVED" == "$INSTALL_APP" ]] || echo "⚠ LaunchServices resolves com.geonhee.lockapps to '$RESOLVED' — remove other copies of LockApps.app"
  # launchd pins the background agent to the signature it was registered with; a rebuilt bundle fails to spawn
  # (EX_CONFIG / Launch Constraint Violation) until it is registered again.
  if "$INSTALL_APP/Contents/MacOS/$APP_NAME" --agent status 2>/dev/null | grep -q enabled; then
    echo "▶ re-registering background agent for the new build"
    # Registering while launchd is still tearing the old job down pins the new job to the old signature
    # (spawn fails with EX_CONFIG), so wait until the job and its process are really gone.
    "$INSTALL_APP/Contents/MacOS/$APP_NAME" --agent unregister >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      launchctl print "gui/$(id -u)/com.geonhee.lockapps.agent" >/dev/null 2>&1 || pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
      sleep 0.5
    done
    sleep 1
    "$INSTALL_APP/Contents/MacOS/$APP_NAME" --agent register || true
  fi
fi

if [[ $RUN -eq 1 ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  if [[ "$CONFIG" != "debug" && -d "$INSTALL_APP" ]]; then open "$INSTALL_APP"; else open "$APP"; fi
fi
