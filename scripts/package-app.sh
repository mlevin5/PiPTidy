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
login_keychain="${HOME}/Library/Keychains/login.keychain-db"
signing_identity=$(security find-identity -v -p codesigning "$login_keychain" 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')
if [ -n "$signing_identity" ]; then
    codesign --force --keychain "$login_keychain" --sign "$signing_identity" "$app_dir" >/dev/null
    echo "Signed with stable Apple Development identity $signing_identity"
else
    codesign --force --sign - "$app_dir" >/dev/null
    echo "Warning: no Apple Development identity found; permissions may reset after rebuilds" >&2
fi
echo "Packaged $app_dir"
