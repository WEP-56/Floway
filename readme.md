# Floway

Floway is a cross-platform proxy client and UI/UX usability experiment. The `main` branch is the primary development line: its runtime base is ported from FlClash and its proxy core is Mihomo. The `vp_core` branch is a frozen, read-only migration track, is no longer developed, and is not a compatibility reference for `main`. Floway uses one proxy core at a time and does not ship a dual-core selector or fallback.

**Current integration status:** `main` carries the FlClash application runtime vendored into this repository (application shell, managers, providers, plugins, l10n, platform projects and build entry points), and renders Floway's own frontend assets on top of it. Only Windows and Android are built and supported. FlClash is treated as the authoritative implementation: Floway does not add defensive fallbacks, and failures are expected to surface through errors and logs instead of being swallowed. The Floway pages still read the preview store for proxy state; repointing them to the ported runtime is tracked item by item in `TODO.md`.

The blue mark in `assets/branding/floway.png` is the active application icon. `assets/branding/floway-inactive.png` is reserved for a future inactive/error state and is not used by the current UI.

## Run

```powershell
flutter pub get
flutter run -d windows
flutter run -d Android-devices
```

Building the Mihomo core binary requires the Go toolchain in addition to the Flutter SDK. A local build host without Go can still run `flutter pub get`, `flutter analyze` and the Flutter test suite.

## License and upstream

Floway is released under the GNU General Public License v3.0; the full text is in `License`. The project is derived from and ports FlClash (https://github.com/chen08209/FlClash), which remains the authoritative implementation and whose copyright notices and license terms are kept. Vendored upstream components keep their own licenses and attribution.