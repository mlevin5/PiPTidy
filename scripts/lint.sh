#!/bin/sh
set -eu
if command -v swiftlint >/dev/null 2>&1; then swiftlint lint --strict; else echo "swiftlint unavailable; skipping"; fi
if command -v swiftformat >/dev/null 2>&1; then swiftformat --lint Sources Tests; else echo "swiftformat unavailable; skipping"; fi

