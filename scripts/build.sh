#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(sed -nE 's/^[[:space:]]*public static let current = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' Sources/CLICore/Version.swift)"
[[ -n "$version" ]] || { echo 'Cannot read icli version' >&2; exit 1; }
mkdir -p dist
# The executable embeds its privacy description; no external app bundle is required.
cat > dist/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.xiao0yy.icli</string>
<key>CFBundleName</key><string>icli</string>
<key>CFBundleVersion</key><string>$version</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>icli reads and manages calendar events when you run calendar commands.</string>
</dict></plist>
PLIST
swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PWD/dist/Info.plist"
cp "$(swift build -c release --show-bin-path)/icli" dist/icli
codesign --force --sign "${ICLI_SIGN_IDENTITY:--}" --identifier dev.xiao0yy.icli dist/icli
codesign --verify dist/icli
[[ "$(dist/icli --version)" == "$version" ]] || { echo 'Binary version mismatch' >&2; exit 1; }
printf 'Built %s/dist/icli (%s)\n' "$PWD" "$version"
