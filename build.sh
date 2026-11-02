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
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
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
fi

if [[ $RUN -eq 1 ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  if [[ "$CONFIG" != "debug" && -d "$INSTALL_APP" ]]; then open "$INSTALL_APP"; else open "$APP"; fi
fi
