# Security and distribution

ScootPiP uses only public APIs and does not log screen content. Debug mode shows diagnostic window metadata. Accessibility-based assistive behavior conflicts with App Sandbox restrictions, so Mac App Store distribution is unlikely without an architectural or policy change. See Apple's [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

Core Graphics metadata is documented at [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29). It does not promise an AX identity.

