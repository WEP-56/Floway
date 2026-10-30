import 'package:uuid/uuid.dart';

import 'snapshot_store.dart';
import 'transport.dart';

enum CoreState {
  stopped,
  preparing,
  starting,
  running,
  applying,
  stopping,
  failed,
}

class CoreStatus {
  const CoreStatus({
    this.state = CoreState.stopped,
    this.generation = 0,
    this.appliedRevision = 0,
    this.configHash,
    this.mixedPort,
    this.upload = 0,
    this.download = 0,
    this.connections = 0,
    this.selected,
  });
  final CoreState state;
  final int generation;
  final int appliedRevision;
  final String? configHash;
  final int? mixedPort;
  final int upload;
  final int download;
  final int connections;
  final String? selected;
  bool get running => state == CoreState.running;

  factory CoreStatus.fromJson(Map<String, dynamic> json) => CoreStatus(
    state: CoreState.values.byName(json['state'] as String),
    generation: json['generation'] as int,
    appliedRevision: json['appliedRevision'] as int,
    configHash: json['configHash'] as String?,
    mixedPort: json['mixedPort'] as int?,
    upload: json['upload'] as int,
    download: json['download'] as int,
    connections: json['connections'] as int,
    selected: json['selected'] as String?,
  );
}

class CoreFailure implements Exception {
  const CoreFailure(this.code, this.message, this.rollbackStatus);
  final String code;
  final String message;
  final String? rollbackStatus;
  @override
  String toString() =>
      '$code: $message${rollbackStatus == 'restored' ? '（已恢复上一配置）' : ''}';
}

class CoreBridge {
  CoreBridge(this.transport);
  final HostTransport transport;
  CoreStatus status = const CoreStatus();
  Map<String, dynamic>? capabilities;

  Future<Map<String, dynamic>> _request(
    String operation, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final response = await transport.request({
      'requestId': const Uuid().v4(),
      'operation': operation,
      'expectedGeneration': status.generation,
      'expectedAppliedRevision': status.appliedRevision,
      'arguments': arguments,
    });
    if (response['ok'] != true) {
      if (response['status'] is Map<String, dynamic>) {
        status = CoreStatus.fromJson(
          response['status'] as Map<String, dynamic>,
        );
      }
      final error = response['error'] as Map<String, dynamic>;
      if (error['code'] == 'HOST_FAILURE') {
        throw const HostTransportException('原生宿主发生故障，需要重启应用');
      }
      throw CoreFailure(
        error['code'] as String,
        error['message'] as String,
        error['rollbackStatus'] as String?,
      );
    }
    final result = response['result'] as Map<String, dynamic>;
    if (operation != 'capabilities') status = CoreStatus.fromJson(result);
    return result;
  }

  Future<void> initialize() async {
    capabilities = await _request('capabilities');
    if (capabilities!['protocolVersion'] != 1) {
      capabilities = null;
      throw const CoreFailure('PROTOCOL_MISMATCH', '原生宿主版本不兼容', null);
    }
    await refresh();
  }

  Future<void> refresh() => _request('status').then((_) {});
  Future<void> start(RuntimeSnapshot snapshot) =>
      _request('start', snapshot.arguments).then((_) {});
  Future<void> apply(RuntimeSnapshot snapshot) =>
      _request('apply', snapshot.arguments).then((_) {});
  Future<void> stop() => _request('stop').then((_) {});
  Future<void> close() => transport.close();
}
