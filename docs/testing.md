# Testing and manual acceptance

Automated tests cover display conversion, clamping, ranking, correlation ambiguity, and mutation failures using fakes.

Phase 2 manual acceptance: grant Screen Recording when prompted, select the PiP row, click **Analyze Screen**, inspect the heatmap and proposed rectangle, then click **Place Optimally**. Analysis excludes ScootPiP and the selected PiP window and prohibits placement over the menu bar or Dock.

GUI acceptance: launch from Xcode; grant Accessibility; open Chrome native PiP; refresh; manually select the actual PiP row; try four corners and direct global x/y/width/height; verify geometry and capture displayed metadata/errors. Titles, layers, mutability, notification behavior, and Chrome identification are unverified until this test is performed. The observer protocol is only a future seam.
