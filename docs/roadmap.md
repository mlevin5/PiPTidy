# Roadmap

- Phase 0–1: native inventory, scoring, manual selection, movement, and resizing.
- Phase 2 (in progress): user-triggered ScreenCaptureKit snapshot, weighted scoring heatmap, exact largest-fit preview, and optimal placement. OCR and continuous re-analysis remain deferred.
- Phase 5: browser extension and Native Messaging host execution.

## Placement intelligence backlog

- [ ] **Cursor-aware movement without breaking PiP controls.** A first version now adds a soft penalty around the current cursor and pauses repositioning whenever the pointer is inside PiP, preserving its play, pause, seek, close, and resize controls. Next: recent cursor trajectory, dwell weighting, and a longer grace period so the video never flees from an attempted click.
- [ ] **Temporal staleness.** Maintain a low-resolution history map. Regions that remain unchanged, lose keyboard focus, have been scrolled past, or have not received cursor dwell can gradually decay in importance. Recently changed, focused, or revisited regions regain weight. Treat “already read” only as an inference; never claim eye tracking without an actual gaze signal.
- [ ] **Fast-motion/game mode.** Calculate coarse frame-difference or block-motion energy at a higher cadence than the full saliency pass. Protect moving connected components and predicted near-future positions while using integral images, dirty-region updates, and a strict per-frame time budget.
- [ ] **Movement stability.** A first version now ignores small changes in proposed position and size. Next: require a meaningful score improvement, cap move frequency, predict short motion trajectories, and prefer resizing in place over repeatedly teleporting PiP.
- [ ] **Focused UI signals.** Weight the frontmost app, key window, focused Accessibility element, active menu/popover, insertion point, selected text, and recently clicked controls without reading or logging their contents.
- [ ] **Classical visual cues.** Combine edge density, local contrast, connected components, motion energy, face-like regions, text-line geometry, and stable HUD-shaped regions. Keep the fast path local and deterministic; no LLM or generative-AI dependency.
- [ ] **Layered analysis cadence.** Run cheap window/cursor/motion updates frequently, medium-cost saliency only on changed tiles, and expensive optional detectors rarely. Cache integral maps and reuse them until their tiles become dirty.
- [ ] **Learn from manual PiP adjustments.** Distinguish automatic writes from subsequent human moves/resizes. Treat an immediate manual adjustment as corrective feedback: remember normalized preferred/avoided zones by display and workspace shape, decay old observations, and bias later placements without hard-locking them. Keep the history on-device, show what was learned, and offer per-display and global reset buttons.
- [ ] **Customizable PiP frames.** Offer optional neon, minimal, high-contrast, and user-color borders through a transparent nonactivating companion overlay that follows PiP. The decoration must never intercept clicks, cover native PiP controls, appear in screen captures used for scoring, or make movement feel laggy. Include a frame-off mode and accessibility-safe contrast choices.
- [ ] **Benchmarks.** Add recorded synthetic motion fixtures and track capture, map update, optimization, end-to-end response latency, CPU use, energy impact, movement count, and protected-object occlusion.

## Release path

- Public beta: free, non-expiring MIT releases used to validate placement quality, performance, browser coverage, and onboarding.
- Beta exit: publish and tag the final public beta, preserve its source and license, and archive the public repository instead of pretending previously granted MIT rights can be revoked.
- Commercial development: continue 1.0 work in a separate private repository, with a 14-day unrestricted trial and $15 one-time license.
- Paid launch: ship a Developer ID signed and notarized build with license recovery, reasonable offline behavior, and a clear refund/support path.
