#!/bin/bash
# Build the Swift Mac app's program for Intel and Apple-silicon Macs (macOS 11 and newer) on a Mac with Xcode,
# into mac/bin/E11Console.zip (just the program; the installer wraps it into an app on each Mac).
#   mac/swift/build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos11.0" -sdk "$(xcrun --show-sdk-path)" \
    -framework Cocoa -framework WebKit -framework UserNotifications -framework LocalAuthentication \
    "$HERE/main.swift" -o "$WORK/E11Console-$arch"
done
lipo -create "$WORK/E11Console-arm64" "$WORK/E11Console-x86_64" -output "$WORK/E11Console"
lipo -info "$WORK/E11Console"
SV="$(grep -Eo 'let SHELL_VERSION = [0-9]+' "$HERE/main.swift" | grep -Eo '[0-9]+$')"
echo "$SV" > "$WORK/SHELL_VERSION"
rm -f "$OUT/E11Console.zip"
(cd "$WORK" && zip -q "$OUT/E11Console.zip" E11Console SHELL_VERSION)
ls -l "$OUT/E11Console.zip"
