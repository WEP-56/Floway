part of 'profile.dart';

/// Explicit protocol parameters. No arbitrary subscription fields reach the core.
class NodeOptions {
  const NodeOptions({
    this.username,
    this.password,
    this.uuid,
    this.cipher,
    this.alterId,
    this.tls,
    this.sni,
    this.skipCertVerify,
    this.fingerprint,
    this.udp,
    this.network,
    this.flow,
    this.alpn,
    this.ws,
    this.reality,
    this.authString,
    this.up,
    this.down,
  });

  final String? username, password, uuid, cipher, sni, fingerprint;
  final String? network, flow, authString;
  final int? alterId, up, down;
  final bool? tls, skipCertVerify, udp;
  final List<String>? alpn;
  final WebSocketOptions? ws;
  final RealityOptions? reality;

  static const _tls = {'sni', 'skip-cert-verify'};
  static const _stream = {
    ..._tls,
    'tls',
    'client-fingerprint',
    'network',
    'alpn',
    'ws-opts',
    'udp',
  };
  static const allowed = <NodeProtocol, Set<String>>{
    NodeProtocol.http: {'username', 'password', 'tls', ..._tls},
    NodeProtocol.socks5: {'username', 'password', 'udp'},
    NodeProtocol.ss: {'password', 'cipher', 'udp'},
    NodeProtocol.vmess: {'uuid', 'cipher', 'alterId', ..._stream},
    NodeProtocol.vless: {'uuid', 'flow', 'reality-opts', ..._stream},
    NodeProtocol.trojan: {'password', ..._stream},
    NodeProtocol.anytls: {'password', ..._tls, 'client-fingerprint', 'udp'},
    NodeProtocol.hysteria: {'auth-str', 'up', 'down', 'alpn', ..._tls},
    NodeProtocol.hysteria2: {'password', ..._tls},
  };

  Map<String, Object?> toJson() => {
    if (username != null) 'username': username,
    if (password != null) 'password': password,
    if (uuid != null) 'uuid': uuid,
    if (cipher != null) 'cipher': cipher,
    if (alterId != null) 'alterId': alterId,
    if (tls != null) 'tls': tls,
    if (sni != null) 'sni': sni,
    if (skipCertVerify != null) 'skip-cert-verify': skipCertVerify,
    if (fingerprint != null) 'client-fingerprint': fingerprint,
    if (udp != null) 'udp': udp,
    if (network != null) 'network': network,
    if (flow != null) 'flow': flow,
    if (alpn != null) 'alpn': alpn,
    if (ws != null) 'ws-opts': ws!.toJson(),
    if (reality != null) 'reality-opts': reality!.toJson(),
    if (authString != null) 'auth-str': authString,
    if (up != null) 'up': up,
    if (down != null) 'down': down,
  };

  factory NodeOptions.fromJson(Object? value) {
    final m = jsonObject(
      value,
      allowed.values.expand((v) => v).toSet(),
      '节点参数',
    );
    String? text(String key) {
      if (!m.containsKey(key)) return null;
      requireConfig(m[key] is String, '节点 $key 必须是字符串');
      return m[key] as String;
    }

    bool? flag(String key) {
      if (!m.containsKey(key)) return null;
      requireConfig(m[key] is bool, '节点 $key 必须是布尔值');
      return m[key] as bool;
    }

    int? number(String key) {
      if (!m.containsKey(key)) return null;
      requireConfig(m[key] is int, '节点 $key 必须是整数');
      return m[key] as int;
    }

    List<String>? protocols;
    if (m.containsKey('alpn')) {
      requireConfig(
        m['alpn'] is List && (m['alpn'] as List).every((v) => v is String),
        'ALPN 必须是字符串列表',
      );
      protocols = List<String>.unmodifiable(m['alpn'] as List);
    }
    return NodeOptions(
      username: text('username'),
      password: text('password'),
      uuid: text('uuid'),
      cipher: text('cipher'),
      alterId: number('alterId'),
      tls: flag('tls'),
      sni: text('sni'),
      skipCertVerify: flag('skip-cert-verify'),
      fingerprint: text('client-fingerprint'),
      udp: flag('udp'),
      network: text('network'),
      flow: text('flow'),
      alpn: protocols,
      ws: m.containsKey('ws-opts')
          ? WebSocketOptions.fromJson(m['ws-opts'])
          : null,
      reality: m.containsKey('reality-opts')
          ? RealityOptions.fromJson(m['reality-opts'])
          : null,
      authString: text('auth-str'),
      up: number('up'),
      down: number('down'),
    );
  }

  void validate(NodeProtocol protocol) {
    requireConfig(
      toJson().keys.every(allowed[protocol]!.contains),
      '${protocol.name} 含未支持或不适用的参数',
    );
    for (final value in [
      username,
      password,
      uuid,
      cipher,
      sni,
      fingerprint,
      network,
      flow,
      authString,
    ]) {
      requireConfig(
        value == null ||
            (utf8.encode(value).length <= 4096 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)),
        '节点参数过长或含控制字符',
      );
    }
    if (protocol == NodeProtocol.http || protocol == NodeProtocol.socks5) {
      requireConfig((username == null) == (password == null), '认证用户名和密码必须同时提供');
      if (username != null) {
        requireConfig(
          username!.isNotEmpty && password!.isNotEmpty,
          '认证用户名和密码不能为空',
        );
        requireConfig(
          protocol != NodeProtocol.http || !username!.contains(':'),
          'HTTP 用户名不能含冒号',
        );
        requireConfig(
          protocol != NodeProtocol.socks5 ||
              (utf8.encode(username!).length <= 255 &&
                  utf8.encode(password!).length <= 255),
          'SOCKS5 认证字段不能超过 255 字节',
        );
      }
    }
    if ([
      NodeProtocol.ss,
      NodeProtocol.trojan,
      NodeProtocol.anytls,
      NodeProtocol.hysteria2,
    ].contains(protocol)) {
      requireConfig(password != null && password!.isNotEmpty, '协议需要非空密码');
    }
    if ([NodeProtocol.vmess, NodeProtocol.vless].contains(protocol)) {
      requireConfig(
        uuid != null && validId(uuid!.toLowerCase()),
        '协议需要有效 UUID',
      );
    }
    if (protocol == NodeProtocol.ss) {
      requireConfig(
        [
          'aes-128-gcm',
          'aes-256-gcm',
          'chacha20-ietf-poly1305',
        ].contains(cipher),
        '当前 Shadowsocks 仅支持 AEAD AES-GCM / ChaCha20',
      );
    }
    if (protocol == NodeProtocol.vmess) {
      requireConfig(
        alterId == null || alterId == 0,
        '当前仅支持 VMess AEAD（alterId: 0）',
      );
      requireConfig(
        cipher == null ||
            [
              'auto',
              'aes-128-gcm',
              'chacha20-poly1305',
              'none',
              'zero',
            ].contains(cipher),
        '不支持的 VMess 加密方式',
      );
    }
    final usesTls =
        tls ??
        (protocol == NodeProtocol.trojan ||
            protocol == NodeProtocol.anytls ||
            protocol == NodeProtocol.hysteria ||
            protocol == NodeProtocol.hysteria2);
    requireConfig(
      usesTls ||
          (sni == null &&
              skipCertVerify != true &&
              fingerprint == null &&
              alpn == null &&
              reality == null),
      'TLS 参数需要启用 TLS',
    );
    requireConfig(
      sni == null ||
          (sni!.isNotEmpty &&
              sni!.length <= 253 &&
              RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*$').hasMatch(sni!)),
      'SNI 必须为 ASCII 主机名',
    );
    requireConfig(
      fingerprint == null || (fingerprint == 'chrome' && reality != null),
      '当前内核仅在 Reality 下支持 chrome 指纹；其他指纹或普通 TLS 指纹不会生效',
    );
    requireConfig(
      network == null || ['tcp', 'ws'].contains(network),
      '当前传输仅支持 TCP / WebSocket',
    );
    requireConfig(ws == null || network == 'ws', 'ws-opts 需要 WebSocket 传输');
    ws?.validate();
    requireConfig(
      flow == null || flow == '' || flow == 'xtls-rprx-vision',
      '未支持的 VLESS flow',
    );
    requireConfig(
      flow == null ||
          flow == '' ||
          (usesTls && (network == null || network == 'tcp')),
      'Vision 需要 TLS 和 TCP 传输',
    );
    reality?.validate();
    requireConfig(
      reality == null || (network == null || network == 'tcp'),
      '当前 Reality 仅支持 TCP 传输',
    );
    if (alpn != null) {
      requireConfig(
        alpn!.isNotEmpty &&
            alpn!.length <= 16 &&
            alpn!.every(
              (s) =>
                  s.isNotEmpty &&
                  utf8.encode(s).length <= 255 &&
                  !RegExp(r'[\x00-\x20\x7f]').hasMatch(s),
            ),
        'ALPN 列表无效',
      );
    }
    if (protocol == NodeProtocol.hysteria) {
      requireConfig(
        authString != null &&
            authString!.trim().isNotEmpty &&
            !['str', 'base64'].contains(authString!.trim().toLowerCase()),
        'Hysteria 需要明确的 auth-str 密码',
      );
      requireConfig(
        [up, down].every((n) => n != null && n > 0 && n <= 1000000),
        'Hysteria 上下行速率必须为 1–1000000 Mbps',
      );
    }
  }
}

class WebSocketOptions {
  WebSocketOptions({this.path = '/', Map<String, String> headers = const {}})
    : headers = Map.unmodifiable(headers);
  final String path;
  final Map<String, String> headers;
  Map<String, Object?> toJson() => {'path': path, 'headers': headers};
  factory WebSocketOptions.fromJson(Object? value) {
    final m = jsonObject(value, {'path', 'headers'}, 'ws-opts');
    requireConfig(
      !m.containsKey('path') || m['path'] is String,
      'WebSocket 路径必须是字符串',
    );
    final headers = m['headers'] ?? <String, dynamic>{};
    requireConfig(
      headers is Map<String, dynamic> &&
          headers.values.every((v) => v is String),
      'WebSocket headers 必须为字符串对象',
    );
    return WebSocketOptions(
      path: m['path'] as String? ?? '/',
      headers: Map<String, String>.from(headers as Map),
    );
  }
  void validate() {
    requireConfig(
      path.startsWith('/') &&
          path.length <= 2048 &&
          !RegExp(r'[\x00-\x20\x7f]').hasMatch(path),
      'WebSocket 路径无效',
    );
    requireConfig(headers.length <= 32, 'WebSocket headers 过多');
    final names = <String>{};
    for (final e in headers.entries) {
      requireConfig(
        RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(e.key) &&
            names.add(e.key.toLowerCase()) &&
            e.value.length <= 4096 &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(e.value),
        'WebSocket header 无效或重复',
      );
      requireConfig(
        ![
          'connection',
          'upgrade',
          'sec-websocket-key',
          'sec-websocket-version',
          'content-length',
          'transfer-encoding',
        ].contains(e.key.toLowerCase()),
        'WebSocket 握手保留字段不能覆盖',
      );
    }
  }
}

class RealityOptions {
  const RealityOptions({required this.publicKey, this.shortId = ''});
  final String publicKey, shortId;
  Map<String, Object?> toJson() => {
    'public-key': publicKey,
    'short-id': shortId,
  };
  factory RealityOptions.fromJson(Object? value) {
    final m = jsonObject(value, {'public-key', 'short-id'}, 'reality-opts');
    requireConfig(
      !m.containsKey('short-id') || m['short-id'] is String,
      'Reality short-id 必须是字符串',
    );
    return RealityOptions(
      publicKey: jsonText(m, 'public-key'),
      shortId: m['short-id'] as String? ?? '',
    );
  }
  void validate() {
    requireConfig(
      RegExp(r'^[A-Za-z0-9_-]{43}=?$').hasMatch(publicKey),
      'Reality 公钥编码无效',
    );
    requireConfig(
      base64Url.decode(base64Url.normalize(publicKey)).length == 32,
      'Reality 公钥长度无效',
    );
    requireConfig(
      shortId.length <= 16 &&
          shortId.length.isEven &&
          RegExp(r'^[0-9a-fA-F]*$').hasMatch(shortId),
      'Reality short-id 无效',
    );
  }
}
