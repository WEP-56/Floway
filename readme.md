# Floway

This branch is the Flutter UI and design-system workspace for Floway. It keeps the current desktop/mobile interface, reusable widgets, themes, and design references while the `vp_core` branch carries the proxy runtime and platform integration.

The app currently launches with the UI's built-in preview data. Runtime integration will return here after `vp_core` stabilizes.

The blue mark in `assets/branding/floway.png` is the active application icon. `assets/branding/floway-inactive.png` is reserved for a future inactive/error state and is not used by the current UI.

## Run

```powershell
flutter pub get
flutter run -d windows
```

Use any Flutter-supported device target to preview the responsive mobile shell.
