#!/usr/bin/env bash
# What the SDK costs a customer's binary.
#
# A budget rather than a measurement: widget.js has one because it ships to
# every page, and this ships inside every copy of somebody's app. Without a
# number that fails a build, a dependency gets added one afternoon and nobody
# notices until an app is 3 MB heavier.
set -euo pipefail

cd "$(dirname "$0")"
BUDGET_KB=${BUDGET_KB:-260}
BUILD=".build/size"
TARGET="arm64-apple-ios15.0-simulator"

rm -rf "$BUILD"; mkdir -p "$BUILD"

xcrun -sdk iphonesimulator swiftc \
  -target "$TARGET" -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -O -module-name Feedoback \
  -emit-module -emit-module-path "$BUILD/Feedoback.swiftmodule" \
  -emit-library -static -o "$BUILD/libFeedoback.a" \
  Sources/Feedoback/*.swift

BYTES=$(size "$BUILD/libFeedoback.a" | awk 'NR>1 {t+=$1} END {print t}')
KB=$(( BYTES / 1024 ))

echo "Feedoback: ${KB} kB of code (budget ${BUDGET_KB} kB)"
if [ "$KB" -gt "$BUDGET_KB" ]; then
  echo "Over budget by $(( KB - BUDGET_KB )) kB." >&2
  echo "This ships inside every copy of a customer's app. Take something out." >&2
  exit 1
fi
