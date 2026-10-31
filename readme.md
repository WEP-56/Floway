# Floway

Floway is a cross-platform proxy client and UI/UX usability experiment. The `main` branch is the primary development line and is intended to use Mihomo as its interim proxy core. The `vp_core` branch is the migration track; once vp_core is stable, Floway will switch to it. Floway will use one proxy core at a time and will not ship a dual-core selector or fallback.

**Current integration status:** the Flutter app on `main` currently runs with built-in preview data. Mihomo has not yet been reconnected to this cleaned frontend branch, so proxy controls are visual/demo behavior until that integration lands.

The blue mark in `assets/branding/floway.png` is the active application icon. `assets/branding/floway-inactive.png` is reserved for a future inactive/error state and is not used by the current UI.

## Run

```powershell
flutter pub get
flutter run -d windows
```

Use any Flutter-supported device target to preview the responsive mobile shell.
