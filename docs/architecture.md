# Architecture

```mermaid
flowchart LR
  UI[Menu bar and debug UI] --> Store[WindowStore]
  Store --> AX[Public Accessibility APIs]
  Store --> CG[Core Graphics inventory]
  Store --> Score[Pure candidate scorer]
  Store --> Geometry[Coordinate conversion and placement]
  Store --> Map[Exact scoring-map optimizer]
  AX -. optional future seam .-> Observer[AX movement observer]
```

AX windows are correlated to window-server metadata conservatively by PID and geometry. `CGWindowListCopyWindowInfo` provides metadata, but no guaranteed stable AX identity; ambiguous matches deliberately report no layer.

Placement is not restricted to corners. A summed-area table evaluates every pixel-aligned map position and searches video sizes from largest to smallest, subject to aspect ratio, bounds, and a configurable mean-cost budget. Area is the primary objective; map cost and deterministic top/left ordering break ties. Phase 1 exposes this pure engine and manual geometry; capture-derived scoring-map generation remains Phase 2.
