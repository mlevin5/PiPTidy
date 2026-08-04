# Security and distribution

PiP Tidy uses only public APIs and does not log screen content. Debug mode shows diagnostic window metadata. Accessibility-based assistive behavior conflicts with App Sandbox restrictions, so Mac App Store distribution is unlikely without an architectural or policy change. See Apple's [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

Core Graphics metadata is documented at [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29). It does not promise an AX identity.

## Developer ID beta release

Direct distribution requires a **Developer ID Application** certificate and Apple notarization; the local Apple Development identity is only for development. Store notary credentials once with `xcrun notarytool store-credentials`, then run:

```sh
PIP_TIDY_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PIP_TIDY_NOTARY_PROFILE="PiPTidy" \
make release
```

This builds the app, signs it, submits a ZIP for notarization, staples the ticket, validates it with `codesign` and Gatekeeper, and produces `.build/release/PiP-Tidy-<version>.zip`. Upload that ZIP to a GitHub Release; the app's manual update command opens the latest-release page.
