import 'package:uuid/uuid.dart';

import 'profile.dart';

/// A share link is a node list, never a complete routing configuration.
/// Convert only explicit, supported semantics into the same typed node model
/// used by Clash/native imports. Never forward arbitrary URI query fields.
ProxyNode parseShareLink(String text) {
  requireConfig(!RegExp(r'[\x00-\x20\x7f]').hasMatch(text), '链接含未编码空白或控制字符');
  final uri = Uri.tryParse(text);
  requireConfig(uri != null, '节点链接语法无效');
  final protocol = switch (uri!.scheme) {
    'http' => NodeProtocol.http,
    'socks5' => NodeProtocol.socks5,
    'vless' => NodeProtocol.vless,
    'trojan' => NodeProtocol.trojan,
    'hysteria2' || 'hy2' => NodeProtocol.hysteria2,
    _ => throw const ConfigurationException(
      '链接协议尚未支持；当前支持 HTTP/SOCKS5/VLESS/Trojan/Hysteria2',
    ),
  };
  requireConfig(
    uri.hasAuthority &&
        RegExp(r'^[a-zA-Z][\w+.-]*://[^/?#]*:[0-9]+(?:[/?#]|$)')
            .hasMatch(text) &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.userInfo.contains('@'),
    '节点链接需要显式端口；路径或认证格式无效',
  );
  final query = uri.queryParametersAll;
  requireConfig(
    query.values.every((values) => values.length == 1),
    '节点链接包含重复参数',
  );
  final simple =
      protocol == NodeProtocol.http || protocol == NodeProtocol.socks5;
  final quic = protocol == NodeProtocol.hysteria2;
  final allowed = simple
      ? <String>{}
      : quic
      ? {'sni', 'insecure', 'allowInsecure'}
      : {
          'security',
          'sni',
          'allowInsecure',
          'insecure',
          'type',
          'host',
          'path',
          'alpn',
          'fp',
          if (protocol == NodeProtocol.vless) ...{
            'encryption',
            'flow',
            'pbk',
            'sid',
            'headerType',
          },
        };
  requireConfig(query.keys.every(allowed.contains), '节点链接包含未支持的参数');
  String? parameter(String key) => query[key]?.single;
  requireConfig(
    !(query.containsKey('insecure') && query.containsKey('allowInsecure')),
    '节点链接含重复证书校验设置',
  );
  final insecure = parameter('insecure') ?? parameter('allowInsecure');
  final skipVerify = switch (insecure) {
    null => null,
    '0' || 'false' => false,
    '1' || 'true' => true,
    _ => throw const ConfigurationException('证书校验设置须为 0/1 或 true/false'),
  };
  final security =
      parameter('security') ??
      (protocol == NodeProtocol.trojan || quic ? 'tls' : 'none');
  requireConfig(
    [
      'none',
      'tls',
      if (protocol == NodeProtocol.vless) 'reality',
    ].contains(security),
    '节点链接的 security 不受支持',
  );
  requireConfig(
    !query.containsKey('encryption') || parameter('encryption') == 'none',
    'VLESS encryption 仅支持 none',
  );
  final network = parameter('type');
  requireConfig(
    network == null || ['tcp', 'ws'].contains(network),
    '当前链接传输仅支持 TCP / WebSocket',
  );
  requireConfig(
    !query.containsKey('headerType') ||
        (parameter('headerType') == 'none' && network != 'ws'),
    'TCP 头部伪装尚未支持',
  );
  requireConfig(
    network == 'ws' ||
        (!query.containsKey('host') && !query.containsKey('path')),
    '链接的 host/path 仅适用于 WebSocket',
  );
  requireConfig(
    !query.containsKey('host') ||
        (parameter('host')!.isNotEmpty &&
            !RegExp(r'[\x00-\x20\x7f]').hasMatch(parameter('host')!)),
    'WebSocket Host 无效',
  );
  requireConfig(
    security == 'reality' ||
        (!query.containsKey('pbk') && !query.containsKey('sid')),
    'Reality 参数需要 security=reality',
  );
  if (security == 'reality') {
    requireConfig(query.containsKey('pbk'), 'Reality 链接缺少公钥');
  }
  String? username, password;
  if (simple) {
    requireConfig(!uri.hasQuery, 'HTTP/SOCKS5 链接尚不支持 query 参数');
    if (uri.userInfo.isNotEmpty) {
      final separator = uri.userInfo.indexOf(':');
      requireConfig(separator > 0, '链接认证需同时提供用户名和密码');
      username = Uri.decodeComponent(uri.userInfo.substring(0, separator));
      password = Uri.decodeComponent(uri.userInfo.substring(separator + 1));
    }
  } else if (protocol != NodeProtocol.vless) {
    password = Uri.decodeComponent(uri.userInfo);
  }
  final node = ProxyNode(
    id: const Uuid().v4(),
    displayName: uri.fragment.isEmpty
        ? '${uri.host}:${uri.port}'
        : Uri.decodeComponent(uri.fragment),
    protocol: protocol,
    server: uri.host,
    port: uri.port,
    options: NodeOptions(
      username: username,
      password: password,
      uuid: protocol == NodeProtocol.vless
          ? Uri.decodeComponent(uri.userInfo)
          : null,
      tls: !simple && !quic ? security != 'none' : null,
      sni: parameter('sni'),
      skipCertVerify: skipVerify,
      fingerprint: parameter('fp'),
      network: network,
      flow: parameter('flow'),
      alpn: parameter('alpn')?.split(','),
      ws: network == 'ws'
          ? WebSocketOptions(
              path: parameter('path') ?? '/',
              headers: {
                if (query.containsKey('host')) 'Host': parameter('host')!,
              },
            )
          : null,
      reality: security == 'reality'
          ? RealityOptions(
              publicKey: parameter('pbk')!,
              shortId: parameter('sid') ?? '',
            )
          : null,
    ),
  );
  node.validate();
  return node;
}
