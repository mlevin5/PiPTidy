#!/bin/sh
set -eu

: "${PIP_TIDY_SIGNING_IDENTITY:?Set PIP_TIDY_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${PIP_TIDY_NOTARY_PROFILE:?Set PIP_TIDY_NOTARY_PROFILE to a notarytool keychain profile}"

version=$(defaults read "$(pwd)/Resources/Info" CFBundleShortVersionString)
app_path=".build/PiP Tidy.app"
output_dir=".build/release"
archive="$output_dir/PiP-Tidy-$version.zip"

make app
mkdir -p "$output_dir"
ditto -c -k --keepParent "$app_path" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$PIP_TIDY_NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
ditto -c -k --keepParent "$app_path" "$archive"
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
echo "Release ready: $archive"
