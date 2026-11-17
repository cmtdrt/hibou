#!/usr/bin/env bash
# Usage: ./scripts/build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

# With Command Line Tools only, the default SDK can be newer than the Swift compiler:
# fall back to the newest compatible SDK.
if [[ -z "${SDKROOT:-}" ]] && ! echo 'import Foundation' | swiftc -typecheck - >/dev/null 2>&1; then
  for sdk in $(ls -d "$(dirname "$(xcrun --show-sdk-path)")"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
    if echo 'import Foundation' | SDKROOT="$sdk" swiftc -typecheck - >/dev/null 2>&1; then
      export SDKROOT="$sdk"
      echo "→ Using SDK: $(basename "$sdk")"
      break
    fi
  done
fi

APP=build/Hibou.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Plain swiftc rather than `swift build`, which breaks on partially updated Command Line Tools.
echo "→ Building…"
swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/Hibou/*.swift \
  -o "$APP/Contents/MacOS/Hibou"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/MenuBarIcon.svg "$APP/Contents/Resources/MenuBarIcon.svg"

echo "→ Generating icon…"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swift scripts/make-icon.swift assets/hibou.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Hibou 2>/dev/null || true
  while pgrep -x Hibou >/dev/null; do sleep 0.2; done
  rm -rf /Applications/Hibou.app
  cp -R "$APP" /Applications/
  open /Applications/Hibou.app
  echo "✓ Installed to /Applications and launched"
fi
