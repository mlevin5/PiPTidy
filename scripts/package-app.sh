#!/bin/sh
set -eu

app_dir=".build/ScootPiP.app"
binary=".build/arm64-apple-macosx/debug/ScootPiP"
if [ ! -x "$binary" ]; then
    binary=".build/debug/ScootPiP"
fi
if [ ! -x "$binary" ]; then
    echo "ScootPiP binary not found; run make build first" >&2
    exit 1
fi

mkdir -p "$app_dir/Contents/MacOS"
cp "$binary" "$app_dir/Contents/MacOS/ScootPiP"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/ScootPiP"
codesign --force --sign - "$app_dir" >/dev/null
echo "Packaged $app_dir"
