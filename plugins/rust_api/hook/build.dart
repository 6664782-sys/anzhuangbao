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

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
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
  final configured = Platform.environment['LIBCLANG_PATH'];
  if (configured != null && configured.isNotEmpty) {
    final directory = Directory(configured);
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      final resources = Directory('${llvmRoot.path}/lib/clang')
          .listSync()
          .whereType<Directory>()
          .where((item) => File('${item.path}/include/stdbool.h').existsSync())
          .first;
      final (target, headers) = switch (input.config.code.targetArchitecture) {
        Architecture.arm64 => (
          'aarch64_linux_android',
          'aarch64-linux-android',
        ),
        Architecture.arm => (
          'armv7_linux_androideabi',
          'arm-linux-androideabi',
        ),
        Architecture.x64 => ('x86_64_linux_android', 'x86_64-linux-android'),
        final architecture => throw UnsupportedError('Android $architecture'),
      };
      final sysroot = '${llvmRoot.path}/sysroot'.replaceAll('\\', '/');
      final resource = resources.path.replaceAll('\\', '/');
      return {
        'LIBCLANG_PATH': directory.path,
        'BINDGEN_EXTRA_CLANG_ARGS_$target':
            '--sysroot="$sysroot" -I"$sysroot/usr/include/$headers" '
            '-resource-dir="$resource"',
      };
    }
  }
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); set LIBCLANG_PATH '
    'to a host libclang directory for bindgen',
  );
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
