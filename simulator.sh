#!/usr/bin/env bash
# Prints an xcodebuild destination for an iPhone simulator that exists.
#
# Not a pinned name: which simulators a machine has is decided by the Xcode
# installed on it, the names change with every iPhone, and a continuous
# integration image can ship the runtimes without creating a single device.
# Pinning "iPhone 17 Pro" is how a green pipeline turns red on an image update
# that changed nothing about this package.
#
# So: take an iPhone on the newest runtime that is actually there, create one
# if there are none, and say out loud which it was. Set FEEDOBACK_DESTINATION
# to override.
set -euo pipefail

if [ -n "${FEEDOBACK_DESTINATION:-}" ]; then
  echo "$FEEDOBACK_DESTINATION"
  exit 0
fi

pick() {
  xcrun simctl list devices available --json | python3 -c '
import json, re, sys

def version(runtime):
    found = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(found.group(1)), int(found.group(2))) if found else (0, 0)

devices = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in devices if "iOS" in r), key=version, reverse=True)

# One already running wins over a newer one that is not, because booting a
# second simulator while the first is up costs minutes on a developer machine
# and buys nothing. On a clean machine nothing is booted and the newest wins.
found = [(d, r) for r in runtimes for d in devices[r] if d["name"].startswith("iPhone")]
booted = [p for p in found if p[0]["state"] == "Booted"]
for device, runtime in (booted or found)[:1]:
    print("|".join([device["udid"], device["name"], runtime.split(".")[-1]]))
'
}

FOUND=$(pick)

if [ -z "$FOUND" ]; then
  # Runtimes but no devices, which is how the macOS runner images arrive.
  RUNTIME=$(xcrun simctl list runtimes --json | python3 -c '
import json, re, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r["isAvailable"] and r["identifier"].find("iOS") != -1]
runtimes.sort(key=lambda r: [int(p) for p in re.findall(r"\d+", r["version"])])
print(runtimes[-1]["identifier"] if runtimes else "")
')
  TYPE=$(xcrun simctl list devicetypes --json | python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"]
         if t["productFamily"] == "iPhone"]
print(types[-1]["identifier"] if types else "")
')
  if [ -z "$RUNTIME" ] || [ -z "$TYPE" ]; then
    echo "No iOS simulator runtime on this machine." >&2
    xcrun simctl list runtimes >&2
    exit 1
  fi
  xcrun simctl create "feedoback-ci" "$TYPE" "$RUNTIME" >/dev/null
  FOUND=$(pick)
fi

IFS="|" read -r UDID NAME RUNTIME <<< "$FOUND"
echo "Testing on $NAME, $RUNTIME" >&2
echo "platform=iOS Simulator,id=$UDID"
