import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flvpcore/ui/app.dart';
import 'package:flvpcore/ui/design/accents.dart';
import 'package:flvpcore/ui/nav.dart';

import 'capture.dart';

/// Captures every page of both shells in light and dark (plus one accent
/// spot check) at the design's reference sizes. The files mirror the naming
/// of the React preview crops in .artifacts/reference so they can be diffed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Captures the replica UI matrix', (tester) async {
    final dir = Platform.isWindows
        ? Directory('.artifacts/ui')
        : await getApplicationSupportDirectory();
    for (final shell in FlvpShellKind.values) {
      final platform = shell == FlvpShellKind.desktop ? 'pc' : 'mobile';
      for (final dark in [false, true]) {
        for (final page in FlvpPageKey.values) {
          await captureShell(
            tester,
            shell: shell,
            page: page,
            dark: dark,
            file:
                '${dir.path}/$platform-${page.name}-${dark ? 'dark' : 'light'}.png',
          );
        }
      }
      await captureShell(
        tester,
        shell: shell,
        accent: FlvpAccent.teal,
        file: '${dir.path}/$platform-dashboard-light-teal.png',
      );
    }
  });
}
