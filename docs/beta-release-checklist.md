# Beta release checklist

## Before packaging

- Run `make test` and `make lint` on a clean checkout.
- Build with the long-lived Apple Development identity used for previous local builds.
- Confirm the bundle identifier and signing identity have not changed unexpectedly.
- Exercise Chrome and Firefox PiP on every available display arrangement.
- Verify fresh Accessibility and Screen Recording onboarding from a test macOS account.

## Acceptance smoke test

1. Launch the packaged app and confirm its menu-bar icon appears.
2. Grant both permissions and relaunch if requested by macOS.
3. Open a muted PiP video and choose **Find Picture-in-Picture**.
4. Analyze without placing, inspect the heatmap, and place the proposal.
5. Enable Live Optimal Placement, change foreground windows, and verify that analyses do not overlap or freeze the menu.
6. Disable Live Optimal Placement and confirm movement stops.
7. Copy diagnostics and verify it contains no image data.

## Distribution blockers

- Adopt a final product name, bundle identifier, and signing identity before recruiting outside testers.
- Add a proper icon, signed DMG or ZIP, Developer ID signing, notarization, and stapling.
- Publish a download page, privacy statement, known-issues list, and feedback address.
- Choose an update mechanism before the first non-beta paid release.
