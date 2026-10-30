import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'compiler.dart';
import 'configuration_library.dart';
import 'profile.dart';

class RuntimeSnapshot {
  const RuntimeSnapshot({required this.revision, required this.config});
  final int revision;
  final CompiledConfig config;
  Map<String, Object?> get arguments => {
    'revision': revision,
    'config': config.text,
    'configHash': config.runtimeHash,
  };
}

class SnapshotStore {
  SnapshotStore(this.root);
  final Directory root;

  Future<void> initialize() async {
    await Directory(p.join(root.path, 'runtime')).create(recursive: true);
    await Directory(p.join(root.path, 'state')).create(recursive: true);
  }

  File _state(String name) => File(p.join(root.path, 'state', '$name.json'));

  Future<void> _atomicJson(File destination, Object value) async {
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(canonicalJson(value), flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Profile> loadProfile() async {
    final client = _state('client');
    if (await client.exists()) {
      final map =
          jsonDecode(await client.readAsString()) as Map<String, dynamic>;
      return Profile.fromJson(map['profile']);
    }
    final file = _state('profile');
    if (!await file.exists()) return Profile.initial();
    return Profile.fromText(await file.readAsString());
  }

  Future<ConfigurationLibrary> loadLibrary() async {
    final file = _state('client');
    if (!await file.exists()) return ConfigurationLibrary();
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return ConfigurationLibrary.fromJson(data['library']);
  }

  void _validateLibrary(
    ConfigurationLibrary? library,
    Profile profile,
    String? selection,
  ) {
    library?.validate();
    if (library?.active case final active?) {
      requireConfig(
        canonicalJson(active.profile.toJson()) ==
                canonicalJson(profile.toJson()) &&
            active.selectedNodeId == selection,
        '活动配置与运行源不一致',
      );
    }
  }

  Future<void> saveProfile(Profile profile) async {
    profile.validate();
    await _atomicJson(_state('profile'), profile.toJson());
  }

  Future<Map<String, dynamic>> loadDeviceSettings() async {
    final client = _state('client');
    if (await client.exists()) {
      final map =
          jsonDecode(await client.readAsString()) as Map<String, dynamic>;
      return _validateDevice(map['device']);
    }
    final file = _state('device');
    if (!await file.exists()) {
      return {'mixedPort': 17890, 'selectedNodeId': null};
    }
    return _validateDevice(jsonDecode(await file.readAsString()));
  }

  Map<String, dynamic> _validateDevice(Object? value) {
    final map = jsonObject(value, {'mixedPort', 'selectedNodeId'}, 'device');
    requireConfig(
      map['mixedPort'] is int &&
          (map['mixedPort'] as int) >= 1024 &&
          (map['mixedPort'] as int) <= 65535,
      '本机端口设置无效',
    );
    requireConfig(
      map['selectedNodeId'] == null || map['selectedNodeId'] is String,
      '节点选择设置无效',
    );
    return map;
  }

  Future<void> saveDeviceSettings(int port, String? selectedId) => _atomicJson(
    _state('device'),
    {'mixedPort': port, 'selectedNodeId': selectedId},
  );

  Future<void> saveClientState(
    Profile profile,
    int port,
    String? selection, {
    ConfigurationLibrary? library,
  }) async {
    profile.validate();
    _validateLibrary(library, profile, selection);
    final device = _validateDevice({
      'mixedPort': port,
      'selectedNodeId': selection,
    });
    await _atomicJson(_state('client'), {
      'profile': profile.toJson(),
      'device': device,
      if (library != null) 'library': library.toJson(),
    });
  }

  Future<RuntimeSnapshot> stage(
    CompiledConfig config, {
    required Profile profile,
    required String? selectedNodeId,
    ConfigurationLibrary? library,
  }) async {
    _validateLibrary(library, profile, selectedNodeId);
    final parent = Directory(p.join(root.path, 'runtime'));
    var revision = 0;
    await for (final entity in parent.list()) {
      final number = int.tryParse(p.basename(entity.path));
      if (number != null && number > revision) revision = number;
    }
    revision++;
    final staging = Directory(p.join(root.path, 'staging', const Uuid().v4()));
    await staging.create(recursive: true);
    await File(p.join(staging.path, 'config.json'))
        .writeAsString(config.text, flush: true);
    await File(p.join(staging.path, 'snapshot.json')).writeAsString(
      canonicalJson({
        'revision': revision,
        'runtimeHash': config.runtimeHash,
        'logicalHash': config.logicalHash,
        'compilerVersion': ConfigCompiler.version,
        'client': {
          if (library != null) 'library': library.toJson(),
          'profile': profile.toJson(),
          'device': {
            'mixedPort': config.mixedPort,
            'selectedNodeId': selectedNodeId,
          },
        },
      }),
      flush: true,
    );
    await staging.rename(p.join(parent.path, '$revision'));
    return RuntimeSnapshot(revision: revision, config: config);
  }

  Future<void> beginApply(
    RuntimeSnapshot snapshot,
    int previousRevision,
  ) async {
    // Non-active sources may have changed since the previous runtime snapshot.
    // Keep the latest committed library when the host rolls back that runtime.
    final previous = await _state('client').exists()
        ? jsonDecode(await _state('client').readAsString())
        : null;
    await _atomicJson(_state('pending'), {
      'revision': snapshot.revision,
      'runtimeHash': snapshot.config.runtimeHash,
      'previousRevision': previousRevision,
      'previousClient': previous,
    });
  }

  Future<void> commit(int revision, String hash) async {
    // Verify the immutable bytes again before publishing the durable pointer.
    final config = File(
      p.join(root.path, 'runtime', '$revision', 'config.json'),
    );
    requireConfig(
      await config.exists() && contentHash(await config.readAsString()) == hash,
      '运行快照摘要不匹配，未提交应用状态',
    );
    final metadata = jsonDecode(
      await File(p.join(root.path, 'runtime', '$revision', 'snapshot.json'))
          .readAsString(),
    ) as Map<String, dynamic>;
    var client = metadata['client'] as Map<String, dynamic>;
    if (await hasPending()) {
      final pending = jsonDecode(
        await _state('pending').readAsString(),
      ) as Map<String, dynamic>;
      if (pending['previousRevision'] == revision &&
          pending['previousClient'] is Map<String, dynamic>) {
        client = pending['previousClient'] as Map<String, dynamic>;
      }
    }
    final profile = Profile.fromJson(client['profile']);
    final device = _validateDevice(client['device']);
    _validateLibrary(
      ConfigurationLibrary.fromJson(client['library']),
      profile,
      device['selectedNodeId'] as String?,
    );
    final recompiled = const ConfigCompiler().compile(
      profile,
      mixedPort: device['mixedPort'] as int,
      selectedNodeId: device['selectedNodeId'] as String?,
    );
    requireConfig(
      metadata['revision'] == revision &&
          metadata['runtimeHash'] == hash &&
          recompiled.runtimeHash == hash,
      '快照元数据与内核配置不一致',
    );
    await _atomicJson(_state('applied'), {
      'revision': revision,
      'runtimeHash': hash,
    });
    await _atomicJson(_state('client'), client);
    await clearPending();
  }

  Future<void> clearPending() async {
    final pending = _state('pending');
    if (await pending.exists()) await pending.delete();
  }

  Future<bool> hasPending() => _state('pending').exists();
}
