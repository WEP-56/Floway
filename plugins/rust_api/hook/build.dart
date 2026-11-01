import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// rquickjs runs bindgen on Android, which must load a *host* libclang. NDKs up to
// r26 ship one next to the compiler (Linux NDKs before r26 under lib64, later
// ones and every macOS NDK under lib). NDK r27+ dropped it, so fall back to an
// installed LLVM — and because that LLVM is not the NDK's, clang can no longer
// derive its resource directory, so bindgen also gets `-resource-dir` plus the
// NDK sysroot that `native_toolchain_rust` normally sets.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(_join(llvmRoot.path, name));
    if (_hasLibclang(directory)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }

  final external = _externalLibclang();
  if (external == null) {
    throw StateError(
      'No libclang for bindgen.\n'
      'rquickjs needs libclang to generate its Android bindings, but\n'
      '${llvmRoot.path}\n'
      'ships none (NDK r27 and later dropped it).\n'
      'Fix one of these:\n'
      '  - install LLVM (winget install LLVM.LLVM) or the Visual Studio\n'
      '    "C++ Clang tools for Windows" component;\n'
      '  - set LIBCLANG_PATH to the folder containing libclang.dll / libclang.so;\n'
      '  - pin an NDK that still ships libclang (e.g. 26.3.11579264) in\n'
      '    android/gradle/libs.versions.toml.',
    );
  }

  final triple = _androidTriple(input.config.code.targetArchitecture);
  final args = _bindgenClangArgs(
    llvmRoot: llvmRoot.path,
    triple: triple,
    libclangDirectory: external,
  );
  stdout.writeln(
    'bindgen: the NDK ships no libclang, using $external'
    '${args == null ? '' : ' with "$args"'}',
  );
  return {
    'LIBCLANG_PATH': external,
    if (triple != null && args != null)
      'BINDGEN_EXTRA_CLANG_ARGS_${triple.replaceAll('-', '_')}': args,
  };
}

/// `--sysroot=<ndk>/sysroot -I<ndk>/sysroot/usr/include/<triple> -resource-dir=…`
String? _bindgenClangArgs({
  required String llvmRoot,
  required String? triple,
  required String libclangDirectory,
}) {
  final sysroot = _join(llvmRoot, 'sysroot');
  final include = triple == null
      ? null
      : _join(sysroot, 'usr', 'include', _sysrootTriple(triple));
  final resourceDir =
      _clangResourceDir(Directory(libclangDirectory).parent.path) ??
      _clangResourceDir(llvmRoot);
  final args = <String>[
    if (Directory(sysroot).existsSync()) '--sysroot=${_slash(sysroot)}',
    if (include != null && Directory(include).existsSync())
      '-I${_slash(include)}',
    if (resourceDir != null) '-resource-dir=${_slash(resourceDir)}',
  ];
  return args.isEmpty ? null : args.join(' ');
}

/// The clang builtin headers (`stdbool.h`, `stddef.h`, …) of an LLVM install.
String? _clangResourceDir(String llvmRoot) {
  final clang = Directory(_join(llvmRoot, 'lib', 'clang'));
  if (!clang.existsSync()) {
    return null;
  }
  final candidates = _directories(clang)
      .where((item) => _hasStdHeaders(item))
      .toList()
    ..sort((a, b) => _versionOf(b).compareTo(_versionOf(a)));
  return candidates.isEmpty ? null : candidates.first.path;
}

bool _hasStdHeaders(Directory versionDirectory) {
  return File(_join(versionDirectory.path, 'include', 'stdbool.h')).existsSync();
}

int _versionOf(Directory directory) {
  return int.tryParse(directory.path.split(Platform.pathSeparator).last) ?? 0;
}

/// The Rust/NDK target triple for the Android architecture being built.
String? _androidTriple(Architecture architecture) {
  return switch (architecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    _ => null,
  };
}

/// The NDK sysroot spells 32-bit arm without the `v7` (`arm-linux-androideabi`).
String _sysrootTriple(String triple) {
  return triple == 'armv7-linux-androideabi' ? 'arm-linux-androideabi' : triple;
}

bool _hasLibclang(Directory directory) {
  if (!directory.existsSync()) {
    return false;
  }
  try {
    return directory.listSync().any(_isLibclang);
  } on FileSystemException {
    return false;
  }
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}

String? _externalLibclang() {
  for (final path in _libclangCandidates()) {
    if (_hasLibclang(Directory(path))) {
      return path;
    }
  }
  return null;
}

Iterable<String> _libclangCandidates() sync* {
  final configured = Platform.environment['LIBCLANG_PATH']?.trim();
  if (configured != null && configured.isNotEmpty) {
    yield configured;
  }
  if (Platform.isWindows) {
    yield r'C:\Program Files\LLVM\bin';
    yield r'C:\Program Files (x86)\LLVM\bin';
    for (final root in const [
      r'C:\Program Files\Microsoft Visual Studio',
      r'C:\Program Files (x86)\Microsoft Visual Studio',
    ]) {
      yield* _visualStudioLlvm(root);
    }
  } else if (Platform.isMacOS) {
    yield '/opt/homebrew/opt/llvm/lib';
    yield '/usr/local/opt/llvm/lib';
    yield '/Applications/Xcode.app/Contents/Developer/Toolchains/'
        'XcodeDefault.xctoolchain/usr/lib';
  } else {
    for (final root in const ['/usr/lib', '/usr/local/lib']) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        continue;
      }
      for (final entity in directory.listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('llvm-')) {
          yield _join(entity.path, 'lib');
        }
      }
    }
  }
}

/// `…/Microsoft Visual Studio/<version>/<edition>/VC/Tools/Llvm/x64/bin`.
Iterable<String> _visualStudioLlvm(String root) sync* {
  final directory = Directory(root);
  if (!directory.existsSync()) {
    return;
  }
  for (final version in _directories(directory)) {
    for (final edition in _directories(version)) {
      yield '${edition.path}${Platform.pathSeparator}VC'
          '${Platform.pathSeparator}Tools${Platform.pathSeparator}Llvm'
          '${Platform.pathSeparator}x64${Platform.pathSeparator}bin';
    }
  }
}

Iterable<Directory> _directories(Directory parent) {
  try {
    return parent.listSync().whereType<Directory>();
  } on FileSystemException {
    return const [];
  }
}

String _join(String first, [String? second, String? third, String? fourth]) {
  final parts = <String>[first];
  for (final part in [second, third, fourth]) {
    if (part != null) {
      parts.add(part);
    }
  }
  return parts.join(Platform.pathSeparator);
}

/// Clang wants forward slashes in arguments on every host.
String _slash(String path) => path.replaceAll(r'\', '/');
