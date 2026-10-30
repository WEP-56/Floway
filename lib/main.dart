import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/bridge.dart';
import 'core/controller.dart';
import 'core/snapshot_store.dart';
import 'core/transport.dart';
import 'ui/app.dart';
import 'ui/store/client_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1080, 720),
      minimumSize: Size(720, 520),
      center: true,
      title: 'FLVPcore',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final support = await getApplicationSupportDirectory();
  final controller = ClientController(
    store: SnapshotStore(support),
    bridge: CoreBridge(
      Platform.isWindows
          ? WindowsHostTransport()
          : const AndroidHostTransport(),
    ),
  );
  final store = FlvpClientStore(controller);
  if (Platform.isWindows) await windowManager.setPreventClose(true);
  runApp(_ClientRuntime(store: store, controller: controller));
}

class _ClientRuntime extends StatefulWidget {
  const _ClientRuntime({required this.store, required this.controller});
  final FlvpClientStore store;
  final ClientController controller;

  @override
  State<_ClientRuntime> createState() => _ClientRuntimeState();
}

class _ClientRuntimeState extends State<_ClientRuntime>
    with WindowListener, WidgetsBindingObserver {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) windowManager.addListener(this);
    unawaited(widget.store.initializeClient());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.controller.initialized) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await widget.store.close();
      await windowManager.destroy();
    } catch (error) {
      _closing = false;
      widget.store.notify('退出失败：$error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) windowManager.removeListener(this);
    widget.store.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FlvpApp(store: widget.store);
}
