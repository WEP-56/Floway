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
## 构建与启动（Windows）

前置：Flutter（stable）、Go 工具链、Rust（cargo）、Visual Studio 2022（含“使用 C++ 的桌面开发”工作负载）。

1. 取内核源码。仓库把 mihomo 内核记为子模块，锁定 FlClash v0.9.2 对应的提交：

   git submodule update --init --recursive

2. 取依赖：

   flutter pub get

3. 直接运行或构建：

   flutter run -d windows
   flutter build windows --debug

内核（Go）与管理员协助进程（Rust）由 setup 构建钩子在 flutter build/run 过程中自动编译，不需要单独执行。dart setup.dart windows 是打包入口（产出 exe/zip 发行物），内部同样会调用 flutter build，日常开发不必先跑它。

产物：build\windows\x64\runner\Debug\Floway.exe；同目录下的 FlClashCore.exe（内核）与 FlClashHelperService.exe（协助进程）沿用上游名称，与安装脚本引用保持一致。

若曾用其它应用目标名构建过：CMake 会把 CMAKE_INSTALL_PREFIX 写成 $<TARGET_FILE_DIR:旧目标名> 存进 build\windows\x64\CMakeCache.txt，改名后再配置会报 No target。删除 build\windows（或 flutter clean）后重新构建即可。

Android：需要 Android SDK/NDK 与 Go 工具链，本轮未验证。