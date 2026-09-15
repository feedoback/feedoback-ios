#!/usr/bin/env bash
# Every check this package has to pass, in one place.
#
# Both continuous integration jobs run this file rather than a list of steps:
# the package is developed here and published on its own, so two workflows
# describe it, and two lists of steps would drift.
set -euo pipefail
cd "$(dirname "$0")"

# The simulator to test on. Pinned by the workflow rather than discovered, so a
# green run means the same thing twice.
DESTINATION=${FEEDOBACK_DESTINATION:-platform=iOS Simulator,OS=latest,name=iPhone 17 Pro}

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Version"
# One version, written in two files that a release reads. A tag is checked
# against this in the release workflow; here we only stop the two drifting.
POD=$(sed -n 's/.*s\.version *= *"\(.*\)".*/\1/p' Feedoback.podspec)
LOG=$(sed -n 's/^## \([0-9][^ ]*\).*/\1/p' CHANGELOG.md | head -1)
if [ "$POD" != "$LOG" ]; then
  echo "Feedoback.podspec says $POD, CHANGELOG.md says $LOG." >&2
  exit 1
fi
echo "$POD"

step "Build without warnings"
# Worth gating on because the toolchain is pinned: a warning here is one we
# wrote, not one a newer compiler started emitting. Several of them are errors
# in the Swift 6 language mode, so this is also what keeps that migration small.
swift build --build-tests -Xswiftc -warnings-as-errors

step "Tests on the host"
# The layers with no UIKit in them — the wire, transport, store and session.
# Fast, and the reason Package.swift lists macOS at all.
swift test

step "Tests on a simulator"
# Not a repeat: redaction and the theme are behind canImport(UIKit), so on the
# host they are compiled out. This is the only run that executes them.
xcodebuild test \
  -scheme Feedoback \
  -destination "$DESTINATION" \
  -derivedDataPath .build/xcode \
  -quiet

step "Size budget"
./size.sh

step "CocoaPods"
if command -v pod >/dev/null 2>&1; then
  pod lib lint --allow-warnings --quick
else
  echo "CocoaPods is not installed; skipped. Continuous integration always runs it."
fi

printf '\n\033[1mAll checks passed.\033[0m\n'
