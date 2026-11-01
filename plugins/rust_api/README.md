# rust_api

Flutter Rust Bridge FFI package for FlClash. The Rust crate under `rust/` is compiled by the Dart build hook in
`hook/build.dart` through Native Assets, so there are no platform folders: Flutter runs the hook during every build
and bundles the resulting `librust_api` itself.

## Requirements

- `rustup`, with the toolchain and targets pinned in `rust/rust-toolchain.toml` (installed on first build).
- The Android NDK for Android builds.
- A host **libclang** for Android builds: `rquickjs` enables its `bindgen` feature on Android (it ships no
  pre-generated Android bindings), and bindgen loads a host libclang at build time. NDK r27 and later no longer ship
  one, so the hook falls back to `LIBCLANG_PATH`, then `C:\Program Files\LLVM\bin` and the Visual Studio LLVM folder.
  Install LLVM (`winget install LLVM.LLVM`) or the VS "C++ Clang tools for Windows" component, or set
  `LIBCLANG_PATH` to the directory that contains `libclang.dll` / `libclang.so`. Pinning an NDK that still ships
  libclang (e.g. `26.3.11579264`) works too.
- `flutter_rust_bridge_codegen` matching the `flutter_rust_bridge` version in `pubspec.yaml`, to regenerate bindings:

```bash
flutter_rust_bridge_codegen generate
```
