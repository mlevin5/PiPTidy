# Roadmap

- Phase 0–1: native inventory, scoring, manual selection, movement, and resizing.
- Phase 2 (in progress): user-triggered ScreenCaptureKit snapshot, weighted scoring heatmap, exact largest-fit preview, and optimal placement. OCR and continuous re-analysis remain deferred.
- Phase 5: browser extension and Native Messaging host execution.

## Placement intelligence backlog

- [ ] **Cursor-aware movement without breaking PiP controls.** Add a soft penalty around the cursor and its recent trajectory, but pause repositioning whenever the pointer is inside the PiP window so its play, pause, seek, close, and resize controls remain clickable. Use hysteresis and a short grace period so the video does not flee from an attempted click.
- [ ] **Temporal staleness.** Maintain a low-resolution history map. Regions that remain unchanged, lose keyboard focus, have been scrolled past, or have not received cursor dwell can gradually decay in importance. Recently changed, focused, or revisited regions regain weight. Treat “already read” only as an inference; never claim eye tracking without an actual gaze signal.
- [ ] **Fast-motion/game mode.** Calculate coarse frame-difference or block-motion energy at a higher cadence than the full saliency pass. Protect moving connected components and predicted near-future positions while using integral images, dirty-region updates, and a strict per-frame time budget.
- [ ] **Movement stability.** Require a meaningful score improvement before moving, cap move frequency, predict short motion trajectories, and prefer resizing in place over repeatedly teleporting the PiP. This prevents jitter in games and video-heavy layouts.
- [ ] **Focused UI signals.** Weight the frontmost app, key window, focused Accessibility element, active menu/popover, insertion point, selected text, and recently clicked controls without reading or logging their contents.
- [ ] **Classical visual cues.** Combine edge density, local contrast, connected components, motion energy, face-like regions, text-line geometry, and stable HUD-shaped regions. Keep the fast path local and deterministic; no LLM or generative-AI dependency.
- [ ] **Layered analysis cadence.** Run cheap window/cursor/motion updates frequently, medium-cost saliency only on changed tiles, and expensive optional detectors rarely. Cache integral maps and reuse them until their tiles become dirty.
- [ ] **User correction signal.** When a user immediately moves PiP away from an automatic placement, remember a local screen-zone preference and reduce the chance of repeating it. Keep this preference on-device and offer a reset button.
- [ ] **Benchmarks.** Add recorded synthetic motion fixtures and track capture, map update, optimization, end-to-end response latency, CPU use, energy impact, movement count, and protected-object occlusion.

## Release path

- Public beta: free, non-expiring MIT releases used to validate placement quality, performance, browser coverage, and onboarding.
- Beta exit: publish and tag the final public beta, preserve its source and license, and archive the public repository instead of pretending previously granted MIT rights can be revoked.
- Commercial development: continue 1.0 work in a separate private repository, with a 14-day unrestricted trial and $15 one-time license.
- Paid launch: ship a Developer ID signed and notarized build with license recovery, reasonable offline behavior, and a clear refund/support path.
