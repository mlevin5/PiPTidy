# Architecture

```mermaid
flowchart LR
  UI[Menu bar and debug UI] --> Store[WindowStore]
  Store --> AX[Public Accessibility APIs]
  Store --> CG[Core Graphics inventory]
  Store --> Score[Pure candidate scorer]
  Store --> Geometry[Coordinate conversion and placement]
  AX -. optional future seam .-> Observer[AX movement observer]
```

AX windows are correlated to window-server metadata conservatively by PID and geometry. `CGWindowListCopyWindowInfo` provides metadata, but no guaranteed stable AX identity; ambiguous matches deliberately report no layer.

