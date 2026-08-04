# PiP Tidy

PiP Tidy is a macOS 14+ beta menu-bar utility that detects a browser picture-in-picture window and moves and resizes it away from important screen content.

The beta recognizes explicitly titled Picture-in-Picture windows from Chrome and Firefox. Manual selection remains available in the details window for browsers that expose different Accessibility metadata.

The placement core searches a scoring map for an exact rectangle: it maximizes video area, then minimizes occlusion cost, rather than selecting one of four corners. Four-corner controls exist only as manual debug shortcuts. Phase 2 supplies the screen-derived scoring map.

Placement controls are available both in the details window and directly from the menu-bar menu. **Live Optimal Placement** detects, analyzes, and moves the PiP periodically until disabled. Analysis happens locally; screenshots are not stored or transmitted.

## Build

```sh
make bootstrap
make generate
make build
make run
make test
make lint
```

Use `make run` for GUI testing. It packages and opens a local `.app`; running the bare executable through `swift run PiPTidy` does not reliably receive keyboard focus on macOS.

The packaging script automatically uses the first valid Apple Development signing identity in the user keychain. Stable signing allows macOS Accessibility and Screen Recording permissions to survive ordinary rebuilds. It refuses to silently replace that identity with an ad-hoc signature; `ALLOW_ADHOC_SIGNING=1 make app` is available only for intentionally disposable builds.

On first launch, grant Accessibility and Screen Recording, then restart the app if macOS asks you to. Open a native Chrome or Firefox PiP window and choose **Find Picture-in-Picture**. Use **Copy diagnostics** in the details window when reporting a problem; it copies metadata and recent errors, never screen pixels.

## Beta limitations

- Browser PiP windows without a recognizable title may require manual selection.
- Live placement analyzes one display at a time and currently uses a fixed four-second interval.
- macOS permission grants are tied to the app's bundle identity and signature. Moving between differently signed development builds can require granting them again.
- The beta has no updater or anonymous analytics. Check the release page manually for updates.

See `docs/` for architecture, security/distribution, testing, and roadmap details.

## GitHub Pages

The static product site lives in `website/`. After pushing the renamed repository to `github.com/meganlevin/PiPTidy`, open **Settings → Pages**, select **GitHub Actions** as the source, and run **Deploy GitHub Pages**. Update the URLs in `Resources/Info.plist`, `website/index.html`, and `.github/ISSUE_TEMPLATE/config.yml` if the GitHub owner or repository differs.
