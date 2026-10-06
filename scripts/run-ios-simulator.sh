#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this script on a Mac with Xcode installed. iPhone Simulator is not available on Linux." >&2
  exit 1
fi

for required_command in xcodebuild xcrun python3; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Missing $required_command. Install Xcode and select its developer tools first." >&2
    exit 1
  fi
done
xcodebuild -version

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$project_root/DerivedData/Simulator"

# Prefer an already booted iPhone; otherwise use the newest available iOS runtime.
# A simulator UDID can optionally be passed as the first argument.
selected_device="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
requested = sys.argv[1]
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not match:
        continue
    version = tuple(int(part) for part in match.group(1).split("-"))
    if version[0] < 17:
        continue
    for device in devices:
        if not device.get("isAvailable", True) or not device["name"].startswith("iPhone"):
            continue
        if requested and device["udid"] != requested:
            continue
        candidates.append((device["state"] == "Booted", version, device))
if not candidates:
    raise SystemExit("No matching iPhone simulator with iOS 17 or newer. Install an iOS simulator runtime in Xcode Settings > Components.")
device = max(candidates, key=lambda item: (item[0], item[1]))[2]
print(device["udid"], device["state"])
' "${1:-}")"
read -r simulator_id simulator_state <<< "$selected_device"

if [[ "$simulator_state" != "Booted" ]]; then
  xcrun simctl boot "$simulator_id"
fi
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

xcodebuild \
  -project "$project_root/QuietReels.xcodeproj" \
  -scheme QuietReels \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcrun simctl install "$simulator_id" \
  "$derived_data/Build/Products/Debug-iphonesimulator/QuietReels.app"
xcrun simctl launch --terminate-running-process "$simulator_id" org.example.QuietReels
echo "Quiet Reels is open in iPhone Simulator."
