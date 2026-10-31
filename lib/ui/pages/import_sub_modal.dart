import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme_scope.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/feedback.dart';

class FlvpImportSubModal extends StatefulWidget {
  const FlvpImportSubModal({
    super.key,
    required this.platform,
    required this.onClose,
  });
  final FlvpPlatform platform;
  final VoidCallback onClose;
  @override
  State<FlvpImportSubModal> createState() => _FlvpImportSubModalState();
}

class _FlvpImportSubModalState extends State<FlvpImportSubModal> {
  String _name = '', _url = '', _server = '', _port = '';
  String _kind = 'remote', _protocol = 'http';
  String? _error;
  bool _busy = false;
  bool get _valid =>
      !_busy &&
      _name.trim().isNotEmpty &&
      switch (_kind) {
        'file' => true,
        'manual' => _server.trim().isNotEmpty && int.tryParse(_port) != null,
        _ => RegExp(
          r'^https?://\S+$',
          caseSensitive: false,
        ).hasMatch(_url.trim()),
      };

  Future<void> _submit() async {
    if (!_valid) return;
    final store = FlvpStoreScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await switch (_kind) {
        'file' => store.importFileConfiguration(_name.trim()),
        'manual' => store.createManualConfiguration(
          _name.trim(),
          _protocol,
          _server.trim(),
          _port,
        ),
        _ => store.importRemoteConfiguration(_name.trim(), _url.trim()),
      };
      if (!mounted) return;
      if (ok) {
        widget.onClose();
      } else {
        setState(() => _error = store.toast?.message ?? '未导入配置');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '导入失败，原配置保持不变');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    setState(() => _url = data?.text?.trim() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpModal(
      platform: widget.platform,
      title: '导入订阅',
      subtitle: '链接 / 本地文件 / 手动配置',
      onClose: _busy ? () {} : widget.onClose,
      footer: [
        FlvpButton(
          variant: FlvpButtonVariant.text,
          label: '取消',
          onPressed: _busy ? null : widget.onClose,
        ),
        FlvpButton(
          label: _busy
              ? '处理中…'
              : (_kind == 'file'
                    ? '选择文件并导入'
                    : (_kind == 'manual' ? '创建' : '导入')),
          onPressed: _valid ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          FlvpSegmented<String>(
            full: true,
            value: _kind,
            options: const [
              FlvpSegmentedOption('remote', '订阅链接'),
              FlvpSegmentedOption('file', '本地文件'),
              FlvpSegmentedOption('manual', '手动创建'),
            ],
            onChanged: (v) {
              if (!_busy) {
                setState(() {
                  _kind = v;
                  _error = null;
                });
              }
            },
          ),
          FlvpField(
            label: '名称',
            value: _name,
            placeholder: '为这份配置命名',
            onChanged: (v) {
              if (!_busy) setState(() => _name = v);
            },
          ),
          if (_kind == 'remote') ...[
            FlvpField(
              label: '订阅链接',
              value: _url,
              placeholder: 'https://',
              mono: true,
              onChanged: (v) {
                if (!_busy) setState(() => _url = v);
              },
            ),
            FlvpTileButton(
              icon: 'ClipboardPaste',
              label: '从剪贴板粘贴',
              onTap: () {
                if (!_busy) _paste();
              },
            ),
          ],
          if (_kind == 'manual') ...[
            FlvpSegmented<String>(
              value: _protocol,
              options: const [
                FlvpSegmentedOption('http', 'HTTP'),
                FlvpSegmentedOption('socks5', 'SOCKS5'),
              ],
              onChanged: (v) {
                if (!_busy) setState(() => _protocol = v);
              },
            ),
            FlvpField(
              label: '服务器',
              value: _server,
              placeholder: 'IP 或域名',
              mono: true,
              onChanged: (v) {
                if (!_busy) setState(() => _server = v);
              },
            ),
            FlvpField(
              label: '端口',
              value: _port,
              placeholder: '1–65535',
              mono: true,
              onChanged: (v) {
                if (!_busy) setState(() => _port = v);
              },
            ),
          ],
          Text(
            _kind == 'manual' ? '当前支持无认证 HTTP / SOCKS5。默认通过此节点代理。' : '支持 flvp-profile v1、Clash 配置及 HTTP/SOCKS5、VLESS、Trojan、Hysteria2 分享链接列表（含 Base64）。文件保存为应用内快照。Clash 节点另支持 SS、VMess、AnyTLS、Hysteria 1；参数按内核能力校验。支持 select 与非惰性 URL-Test/Fallback、基础规则及 redir-host DNS 上游/fallback；Fake-IP、Geo、provider 尚未支持。未知字段会拒绝整份导入；订阅不会覆盖本机监听和系统 DNS 设置。',
            style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
          ),
          if (_error != null)
            Text(_error!, style: flvpText(12, color: colors.warn)),
        ],
      ),
    );
  }
}
