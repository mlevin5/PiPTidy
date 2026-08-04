# Privacy

PiP Tidy performs placement analysis entirely on the Mac. It captures the selected display through Apple's ScreenCaptureKit, immediately reduces that image to a low-resolution importance map in memory, and does not save or transmit the image.

The app does not include analytics, advertising, accounts, or network services. Its details window can display application names, window titles, geometry, and recent errors for local diagnosis. **Copy diagnostics** copies only that visible metadata and permission state to the clipboard; sending it is always the user's choice.

Accessibility permission is used to enumerate, move, and resize windows. Screen Recording permission is used to calculate areas that the picture-in-picture window should avoid.

This statement describes version 0.2.0 beta. It must be revised before adding telemetry, crash reporting, update checks, licensing, or any network feature.
