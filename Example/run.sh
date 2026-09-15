#!/usr/bin/env bash
# Builds the example and puts it on a booted simulator.
#
# Two swiftc calls rather than an Xcode project: the SDK has no dependencies,
# so there is nothing for a project file to manage, and a script is something
# anyone can read. Xcode users can open Package.swift instead.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD=".build/example"
APP="$BUILD/FeedobackExample.app"
TARGET="arm64-apple-ios15.0-simulator"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

rm -rf "$BUILD"
mkdir -p "$APP"

echo "Building the SDK for the simulator…"
xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" -sdk "$SDK" \
  -module-name Feedoback \
  -emit-module -emit-module-path "$BUILD/Feedoback.swiftmodule" \
  -emit-library -static -o "$BUILD/libFeedoback.a" \
  Sources/Feedoback/*.swift

echo "Building the example…"
xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" -sdk "$SDK" \
  -I "$BUILD" -L "$BUILD" -lFeedoback \
  -parse-as-library \
  -o "$APP/FeedobackExample" \
  Example/FeedobackExample/*.swift

cp Example/FeedobackExample/Info.plist "$APP/Info.plist"
cp Sources/Feedoback/PrivacyInfo.xcprivacy "$APP/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.feedoback.example" "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string FeedobackExample" "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Feedoback" "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" "$APP/Info.plist" 2>/dev/null || true

# "booted" is whichever simulator simctl feels like when several are, and a
# watch is not where this belongs. Resolve an iPhone, or take one by name.
DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun simctl list devices booted -j \
    | python3 -c 'import json,sys
data = json.load(sys.stdin)["devices"]
for runtime, devices in data.items():
    if "iOS" not in runtime: continue
    for device in devices:
        if device.get("state") == "Booted" and "iPhone" in device["name"]:
            print(device["udid"]); raise SystemExit')
fi
if [ -z "$DEVICE" ]; then
  echo "No booted iPhone simulator. Boot one, or pass a name or UDID." >&2
  exit 1
fi

echo "Installing onto $DEVICE…"
xcrun simctl install "$DEVICE" "$APP"
echo "Installed com.feedoback.example"
