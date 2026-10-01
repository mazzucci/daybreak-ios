#!/bin/bash
# Build Daybreak (or take a prebuilt Daybreak.app), boot a simulator, install the app, set the location to
# Weston, MA (42.36,-71.29) and launch it.
#
#   scripts/run-in-simulator.sh                  # iPhone 17
#   scripts/run-in-simulator.sh --ipad           # iPad Pro 13-inch (M5)
#   scripts/run-in-simulator.sh path/to/Daybreak.app
set -euo pipefail

DEVICE="iPhone 17"
APP=""
for arg in "$@"; do
  case "$arg" in
    --ipad) DEVICE="iPad Pro 13-inch (M5)" ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) APP="$arg" ;;
  esac
done

if [ -z "$APP" ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  xcodebuild -project "$ROOT/Daybreak.xcodeproj" -scheme Daybreak -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$ROOT/build" -quiet build
  APP="$ROOT/build/Build/Products/Debug-iphonesimulator/Daybreak.app"
fi

# Shows the simulator window; over SSH (no GUI session) it can't, and the simulator runs headless instead.
open -a Simulator || echo "Couldn't open Simulator.app; carrying on without its window." >&2
xcrun simctl boot "$DEVICE" 2>/dev/null || true # already booted is fine
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl privacy "$DEVICE" grant location app.daybreak.ios
xcrun simctl location "$DEVICE" set 42.36,-71.29
xcrun simctl terminate "$DEVICE" app.daybreak.ios 2>/dev/null || true
xcrun simctl launch "$DEVICE" app.daybreak.ios
