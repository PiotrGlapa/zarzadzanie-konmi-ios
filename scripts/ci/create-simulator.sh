#!/usr/bin/env bash
# Tworzy symulator iPhone 15 Pro z najnowszym środowiskiem iOS 18.x (urządzenie odniesienia, plan.md) — obraz runnera go nie ma.
# Zapisuje destynację xcodebuild do SIMULATOR_DESTINATION w $GITHUB_ENV.
set -euo pipefail

runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-18-")]
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(runtimes[-1]["identifier"])
')"

udid="$(xcrun simctl create "iPhone 15 Pro" "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro" "$runtime")"
echo "Symulator iPhone 15 Pro: $udid ($runtime)"
echo "SIMULATOR_DESTINATION=platform=iOS Simulator,id=$udid" >> "$GITHUB_ENV"
