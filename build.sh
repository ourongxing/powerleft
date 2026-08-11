#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/dist/PowerLeft.app"
derived_data="$project_dir/.build"
product="$derived_data/Build/Products/Release/PowerLeft.app"
previous_app="$project_dir/dist/PeripheralBattery.app"
legacy_app="$project_dir/dist/JZM5BatteryTray.app"
signing_identity=${CODE_SIGN_IDENTITY:--}

rm -rf "$app" "$previous_app" "$legacy_app" "$derived_data"
xcodebuild \
  -project "$project_dir/PowerLeft.xcodeproj" \
  -scheme PowerLeft \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p "$project_dir/dist"
ditto "$product" "$app"

codesign --force --deep --sign "$signing_identity" "$app"
echo "$app"
