#!/bin/sh
set -eu

app_dir=".build/PiP Tidy.app"
binary="$(swift build --show-bin-path)/PiPTidy"
if [ ! -x "$binary" ]; then
    echo "PiPTidy binary not found; run make build first" >&2
    exit 1
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary" "$app_dir/Contents/MacOS/PiPTidy"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Assets/AppIcon-1024.png "$app_dir/Contents/Resources/AppIcon-1024.png"
chmod +x "$app_dir/Contents/MacOS/PiPTidy"
login_keychain="${HOME}/Library/Keychains/login.keychain-db"
signing_identity="${PIP_TIDY_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning "$login_keychain" 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')}"
if [ -n "$signing_identity" ]; then
    # Resolve the identity from login explicitly, but let codesign use the full
    # trust search so the chain can reach Apple's root in System Roots.
    if codesign --force --sign "$signing_identity" "$app_dir" >/dev/null; then
        echo "Signed with stable Apple Development identity $signing_identity"
    else
        echo "Development signing failed. Refusing to replace it with an unstable ad-hoc signature." >&2
        echo "Fix the signing identity, or explicitly set ALLOW_ADHOC_SIGNING=1 for a disposable build." >&2
        if [ "${ALLOW_ADHOC_SIGNING:-0}" != "1" ]; then exit 1; fi
        codesign --force --sign - "$app_dir" >/dev/null
    fi
else
    if [ "${ALLOW_ADHOC_SIGNING:-0}" != "1" ]; then
        echo "No Apple Development identity found. Refusing an ad-hoc signature because it resets macOS permissions." >&2
        echo "Set ALLOW_ADHOC_SIGNING=1 only for a disposable build." >&2
        exit 1
    fi
    codesign --force --sign - "$app_dir" >/dev/null
    echo "Warning: using an ad-hoc signature; permissions may reset after rebuilds" >&2
fi
echo "Packaged $app_dir"
