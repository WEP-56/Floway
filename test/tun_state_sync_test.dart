import 'dart:io';

import 'package:flvpcore/core/configuration_library.dart';
import 'package:flvpcore/core/profile.dart';
import 'package:flvpcore/core/snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// TUN 开关只改 profile 时，配置仓库里的活动条目会与运行源不一致。
/// store 会直接拒绝保存，而此时传输已经切走——表现就是
/// 「一开 TUN 连接就被关掉，再点启动提示活动配置与运行源不一致」。
void main() {
  late Directory root;
  late SnapshotStore store;
  final base = Profile.initial();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flvp-store-tun-');
    store = SnapshotStore(root);
    await store.initialize();
  });
  tearDown(() => root.delete(recursive: true));

  ConfigurationLibrary libraryWith(Profile profile, String selection) =>
      ConfigurationLibrary(
        activeId: 'b1e6f0a2-3c4d-4e5f-8a9b-0c1d2e3f4a5b',
        sources: [
          ConfigurationSource(
            id: 'b1e6f0a2-3c4d-4e5f-8a9b-0c1d2e3f4a5b',
            name: '测试订阅',
            kind: ConfigurationSourceKind.remote,
            original: 'proxies: []',
            profile: profile,
            selectedNodeId: selection,
            updatedAt: DateTime.utc(2026, 10, 31),
            url: 'https://example.test/sub',
          ),
        ],
      );

  test('只改 profile 不改活动配置时，保存被拒绝', () async {
    final library = libraryWith(base, directTarget);
    final withTun = base.copyWith(tun: const TunOptions(enabled: true));
    await expectLater(
      store.saveClientState(withTun, 17890, directTarget, library: library),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('活动配置与运行源不一致'),
        ),
      ),
    );
  });

  test('同步活动配置后可以保存，并能被重新加载', () async {
    final withTun = base.copyWith(tun: const TunOptions(enabled: true));
    final library = libraryWith(
      base,
      directTarget,
    ).saveActive(withTun, directTarget);
    await store.saveClientState(withTun, 17890, directTarget, library: library);
    final reloaded = await store.loadProfile();
    expect(reloaded.tun.enabled, isTrue);
    final reloadedLibrary = await store.loadLibrary();
    expect(reloadedLibrary.active!.profile.tun.enabled, isTrue);
  });
}
