#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/dist/PowerLeft.app"
previous_app="$project_dir/dist/PeripheralBattery.app"
legacy_app="$project_dir/dist/JZM5BatteryTray.app"

rm -rf "$app" "$previous_app" "$legacy_app"
mkdir -p "$app/Contents/MacOS"
cp "$project_dir/Info.plist" "$app/Contents/Info.plist"

swiftc "$project_dir/JZM5BatteryTray.swift" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -framework IOKit \
  -framework CoreFoundation \
  -framework MultipeerConnectivity \
  -framework ServiceManagement \
  -o "$app/Contents/MacOS/PowerLeft"

codesign --force --deep --sign - "$app"
echo "$app"
