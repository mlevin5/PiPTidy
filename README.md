# ScootPiP

ScootPiP is an experimental macOS 14+ menu-bar utility for inspecting, selecting, moving, and resizing a picture-in-picture window with public Accessibility APIs.

Phase 1 deliberately requires manual selection. It does not capture the screen, identify Chrome PiP automatically, track the pointer, run a browser extension, or move any window without a user action.

The placement core searches a scoring map for an exact rectangle: it maximizes video area, then minimizes occlusion cost, rather than selecting one of four corners. Four-corner controls exist only as manual debug shortcuts. Phase 2 supplies the screen-derived scoring map.

Phase 2 controls are available both in the debug window and directly from the menu-bar menu. **Live Optimal Placement** refreshes, analyzes, and moves the manually selected PiP every three seconds until disabled.

## Build

```sh
make bootstrap
make generate
make build
make run
make test
make lint
```

Use `make run` for GUI testing. It packages and opens a local `.app`; running the bare executable through `swift run` does not reliably receive keyboard focus on macOS.

The packaging script automatically uses the first valid Apple Development signing identity in the user keychain. Stable signing allows macOS Accessibility and Screen Recording permissions to survive ordinary rebuilds; it falls back to ad-hoc signing with a warning when no identity is available.

Launch from Xcode, grant Accessibility permission, open a native Chrome PiP window, refresh the Debug Window, select its row, and test corner or direct global top-left geometry controls. Record the displayed AX fields, CG layer, and errors: Chrome behavior remains empirically unverified.

See `docs/` for architecture, security/distribution, testing, and roadmap details.
