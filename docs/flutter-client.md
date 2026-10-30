# FLVPcore Flutter client

Windows / Android development milestone M0.1: loopback HTTP/SOCKS5 proxy with shared strict configuration, real native state and restart with rollback. The current design replica is connected through `FlvpClientStore`; the older `ClientShell` editor is retained as source, but is not the application entry point.

The production entry point loads the existing `path_provider` application support directory directly (no additional directory), including previously saved HTTP/SOCKS5 nodes, rules, selection and mixed port. It does not automatically connect. Power, node selection, routing mode and mixed-port changes invoke the real controller. Appearance changes never apply/restart the native core. Port input is debounced before validation and publication; native apply failure restores the displayed applied settings.

Traffic uses differences between native byte counters divided by monotonic elapsed sample time. Generation changes reset counter baselines, and observed totals survive configuration applies. GB values use decimal bytes. “Total” currently means observed traffic during this client process, not a persisted lifetime total. Runtime duration starts when this client first observes the running service; it is not a recovered native start timestamp. No demonstration traffic, subscriptions or nodes appear in production. The demo store remains available for visual capture tests.

Windows window close waits for settings and native shutdown, then destroys the custom window. Android UI disposal does not stop its foreground service; resuming the app refreshes native status. System proxy, TUN/VPN, subscriptions, node latency tests, automatic startup, tray residency and advanced core settings are not implemented; their store actions explicitly report that fact and do not simulate success. Other design-only actions (such as update checks and backup dialogs) are still placeholders; theme choices are not yet persisted. The new pages do not yet expose local node/rule editors or profile import/export; existing profiles can still be loaded.

Build from the repository root with `tools/build_windows.ps1` or `tools/build_android.ps1`. Native hosts must be built before running Flutter; the Windows CMake install step includes its host executable, while Android packages its JNI libraries from jniLibs.

See [implementation, validation and remaining work](m0-implementation.md). Its UI editing descriptions record the original M0 shell, not the current design replica. Full architecture documents are a design baseline and do not imply all features are implemented.

From the repository root: `flutter analyze`, `flutter test`, and `flutter test integration_test/windows_smoke_test.dart -d windows` (or an Android device). Android integration tests are also implemented in that shared test file.
