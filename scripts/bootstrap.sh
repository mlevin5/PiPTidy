#!/bin/sh
set -eu
for tool in xcodegen swiftlint pnpm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then brew install "$tool"; else echo "$tool missing (Homebrew unavailable)"; exit 1; fi
    fi
done

