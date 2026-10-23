#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="app.reviewwatcher"
APP_NAME="ReviewWatcher"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/$APP_NAME.app"
ICONSET="$ROOT/build/$APP_NAME.iconset"
# A release tarball carries no git history, so the updater passes the release's version in.
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert is missing: brew install librsvg" >&2; exit 1; }

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Review Watcher</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$ROOT/Resources/logo.svg" -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ROOT/Resources/logo.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns"
rm -rf "$ICONSET"

# Notification attachments: the same mark recoloured, since macOS cannot tint a banner.
STATUS_SVG="$ROOT/build/status.svg"
for variant in "success:#4ADE80:#16A34A" "failed:#FB7185:#DC2626" "pending:#FCD34D:#D97706" \
               "todo:#D1D5DB:#6B7280" "progress:#60A5FA:#2563EB"; do
    name="${variant%%:*}"
    colors="${variant#*:}"
    sed -e "s/#FC8A3A/${colors%%:*}/" -e "s/#E24329/${colors##*:}/" "$ROOT/Resources/logo.svg" > "$STATUS_SVG"
    rsvg-convert -w 256 -h 256 "$STATUS_SVG" -o "$APP/Contents/Resources/status-$name.png"
done
rm -f "$STATUS_SVG"

# Menu bar glyph: black on clear, so AppKit can tint it as a template for light and dark bars.
rsvg-convert -w 24 -h 18 "$ROOT/Resources/menubar.svg" -o "$APP/Contents/Resources/menubar.png"
rsvg-convert -w 48 -h 36 "$ROOT/Resources/menubar.svg" -o "$APP/Contents/Resources/menubar@2x.png"

swiftc -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit -framework SwiftUI -framework UserNotifications \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    "$ROOT"/Sources/*.swift

# Signing covers the resources too, so the icon must be in place before this runs.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo "built $APP"
