#!/bin/bash
# E11 Console for Mac — installer.
#   Install:  curl -fsSL https://console.e11hq.com/install | bash
#   Test copy: curl -fsSL https://test.e11hq.com/install | bash
# Puts the app together and signs it on this Mac with tools that ship with macOS, so no Apple Developer
# account (and no "unidentified developer" warning) is needed. Safe to run again to reinstall.
#   Back to the earlier app: curl -fsSL https://console.e11hq.com/install/legacy | bash
set -u
SERVER="${E11_SERVER:-__SERVER__}"
APP_NAME="E11 Console"
BUNDLE_ID="ae.e11.console.client"
[ "$SERVER" != "https://console.e11hq.com" ] && { APP_NAME="E11 Console Test"; BUNDLE_ID="ae.e11.console.client.test"; }

bold() { printf "\n\033[1m%s\033[0m\n" "$1"; }
fail() { printf "\n\033[31mInstall failed:\033[0m %s\nSend a screenshot of this window to your Admin.\n" "$1"; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "This installer is for Mac."
printf "\033[1m%s installer\033[0m  (%s)\n" "$APP_NAME" "$SERVER"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUILD="$WORK/$APP_NAME.app"

# The Swift app (macOS 11 and newer) when the server has it; otherwise — or with E11_LEGACY=1, or from
# <server>/install/legacy — the earlier script app, built here with osacompile.
LEGACY="${E11_LEGACY:-__LEGACY__}"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "${MACOS_MAJOR:-0}" -lt 11 ] 2>/dev/null && LEGACY=1

bold "1/4  Downloading…"
curl -fsSL "$SERVER/install/AppIcon.png" -o "$WORK/AppIcon.png" || fail "Couldn't download the app icon"
if [ "$LEGACY" != "1" ]; then
  if curl -fsSL "$SERVER/install/E11Console.zip" -o "$WORK/E11Console.zip" 2>/dev/null && unzip -q -o "$WORK/E11Console.zip" -d "$WORK/bin" 2>/dev/null && [ -s "$WORK/bin/E11Console" ]; then :; else LEGACY=1; fi
fi
if [ "$LEGACY" = "1" ]; then
  curl -fsSL "$SERVER/install/main.js" -o "$WORK/main.js" || fail "Couldn't download the app from $SERVER"
  # (it's the newest this Mac can have: no update bar asking for the Swift app)
  sed -i '' 's/var SHELL_VERSION = [0-9]*;/var SHELL_VERSION = 99;/' "$WORK/main.js"
fi

bold "2/4  Building the app…"
ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/AppIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
  sips -z $((s*2)) $((s*2)) "$WORK/AppIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
done
if [ "$LEGACY" = "1" ]; then
  osacompile -l JavaScript -s -o "$BUILD" "$WORK/main.js" || fail "macOS couldn't build the app (osacompile)."
  RES="$BUILD/Contents/Resources"; PL="$BUILD/Contents/Info.plist"
  iconutil -c icns "$ICONSET" -o "$RES/applet.icns" || fail "Couldn't create the app icon."
  rm -f "$RES/Assets.car"
  plutil -remove CFBundleIconName "$PL" >/dev/null 2>&1
  plutil -replace CFBundleIconFile -string "applet" "$PL"
  plutil -replace CFBundleShortVersionString -string "2.0.0" "$PL"
  plutil -replace CFBundleVersion -string "2" "$PL"
  plutil -replace OSAAppletShowStartupScreen -bool NO "$PL" >/dev/null 2>&1
else
  RES="$BUILD/Contents/Resources"; PL="$BUILD/Contents/Info.plist"
  mkdir -p "$BUILD/Contents/MacOS" "$RES"
  cp "$WORK/bin/E11Console" "$BUILD/Contents/MacOS/$APP_NAME" && chmod 755 "$BUILD/Contents/MacOS/$APP_NAME" || fail "Couldn't put the app together."
  if [ -s "$WORK/bin/Assets.car" ]; then
    # the everyday icon in Apple's glass style (macOS 26 draws it in glass; older macOS uses AppIcon.icns)
    cp "$WORK/bin/Assets.car" "$RES/Assets.car" && cp "$WORK/bin/AppIcon.icns" "$RES/AppIcon.icns" || fail "Couldn't put the app icon in."
  else
    iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns" || fail "Couldn't create the app icon."
  fi
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$PL"
  plutil -replace CFBundleExecutable -string "$APP_NAME" "$PL"
  plutil -replace CFBundlePackageType -string "APPL" "$PL"
  plutil -replace CFBundleIconFile -string "AppIcon" "$PL"
  [ -s "$RES/Assets.car" ] && plutil -replace CFBundleIconName -string "AppIcon" "$PL"
  plutil -replace CFBundleShortVersionString -string "3.0.0" "$PL"
  plutil -replace CFBundleVersion -string "$(cat "$WORK/bin/SHELL_VERSION" 2>/dev/null || echo 7)" "$PL"
  plutil -replace CFBundleInfoDictionaryVersion -string "6.0" "$PL"
  plutil -replace LSMinimumSystemVersion -string "11.0" "$PL"
  plutil -replace NSPrincipalClass -string "NSApplication" "$PL"
  plutil -replace NSHighResolutionCapable -bool YES "$PL"
  plutil -replace NSSupportsAutomaticGraphicsSwitching -bool YES "$PL"
  plutil -replace NSAppTransportSecurity -json '{"NSAllowsLocalNetworking":true}' "$PL"
fi
plutil -replace CFBundleName -string "$APP_NAME" "$PL"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$PL"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PL"
plutil -replace LSApplicationCategoryType -string "public.app-category.productivity" "$PL"
plutil -replace NSHumanReadableCopyright -string "E11 Agency" "$PL"
plutil -replace E11ServerURL -string "$SERVER" "$PL"
# Shared task links: e11console://task/<id> (test copy: e11console-test://) open in this app
SCHEME="e11console"; [ "$SERVER" != "https://console.e11hq.com" ] && SCHEME="e11console-test"
plutil -replace CFBundleURLTypes -json "[{\"CFBundleURLName\":\"$BUNDLE_ID.link\",\"CFBundleURLSchemes\":[\"$SCHEME\"]}]" "$PL"

bold "3/4  Signing it for this Mac…"
codesign --force --deep --sign - "$BUILD" >/dev/null 2>&1 || fail "codesign couldn't sign the app."

bold "4/4  Installing into Applications…"
DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
osascript -e "with timeout of 3 seconds" -e "tell application id \"$BUNDLE_ID\" to quit" -e "end timeout" >/dev/null 2>&1
# The old stand-alone E11 Console (local data) is replaced; its data stays on the Desktop
osascript -e "with timeout of 3 seconds" -e "tell application id \"ae.e11.console\" to quit" -e "end timeout" >/dev/null 2>&1
sleep 1
pkill -f "/$APP_NAME.app/Contents/MacOS/" >/dev/null 2>&1
rm -rf "$DEST/$APP_NAME.app"
ditto "$BUILD" "$DEST/$APP_NAME.app" || fail "Couldn't copy the app into $DEST."
xattr -cr "$DEST/$APP_NAME.app" >/dev/null 2>&1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP_NAME.app" >/dev/null 2>&1

printf "\n\033[32mDone!\033[0m %s is in %s.\nOpening it now — sign in with your work email. You can close this window.\n" "$APP_NAME" "$DEST"
open "$DEST/$APP_NAME.app"
