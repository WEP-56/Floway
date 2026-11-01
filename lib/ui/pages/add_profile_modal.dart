import 'dart:async';

import 'package:floway/common/app_localizations.dart';
import 'package:floway/common/string.dart';
import 'package:floway/pages/scan.dart';
import 'package:floway/providers/providers.dart';
import 'package:floway/ui/navigator.dart';
import 'package:floway/views/profiles/custom/custom.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/theme_scope.dart';
import '../design/tokens.dart';
import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/feedback.dart';
import '../widgets/upstream_page.dart';

/// 「添加配置」：链接 / 本地文件 / 二维码 / 自定义四种上游入口，
/// 全部落在 Floway 的弹层与表单外观上，动作直接调用上游 `profilesAction`。
class FlvpAddProfileModal extends ConsumerStatefulWidget {
  const FlvpAddProfileModal({
    super.key,
    required this.platform,
    required this.onClose,
  });

  final FlvpPlatform platform;
  final VoidCallback onClose;

  @override
  ConsumerState<FlvpAddProfileModal> createState() =>
      _FlvpAddProfileModalState();
}

enum _AddKind { link, file, qr, custom }

class _FlvpAddProfileModalState extends ConsumerState<FlvpAddProfileModal> {
  _AddKind _kind = _AddKind.link;
  String _name = '';
  String _url = '';
  String? _error;
  bool _busy = false;

  bool get _mobile => widget.platform == FlvpPlatform.mobile;

  List<String> get _links => [
    for (final line in _url.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  bool get _linkValid =>
      _links.isNotEmpty && _links.every((link) => link.isUrl || link.isShareLink);

  String get _actionLabel => switch (_kind) {
    _AddKind.link => _busy ? '正在导入…' : '导入',
    _AddKind.file => _busy ? '正在导入…' : '选择文件',
    _AddKind.qr => _mobile ? '打开相机' : '选择图片',
    _AddKind.custom => '创建并打开',
  };

  bool get _canSubmit => switch (_kind) {
    _AddKind.link => !_busy && _linkValid,
    _AddKind.file => !_busy,
    _AddKind.qr => !_busy,
    _AddKind.custom => !_busy,
  };

  void _fail(Object error) {
    final message = userFacingErrorMessage(error, currentAppLocalizations);
    if (!mounted) return;
    setState(() => _error = message);
    FlvpStoreScope.read(context).notify(message);
  }

  Future<void> _submitLink() async {
    final action = ref.read(profilesActionProvider.notifier);
    final links = _links;
    final label = _name.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (links.length > 1) {
        await action.addProfilesFromLinks(links);
      } else {
        await action.addProfileFromLink(
          links.first,
          label: label.isEmpty ? null : label,
        );
      }
      if (mounted) widget.onClose();
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profilesActionProvider.notifier).addProfileFormFile();
      if (mounted) widget.onClose();
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitQrCode() async {
    final action = ref.read(profilesActionProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_mobile) {
        // 桌面用图片识别：选一张含二维码的图片。
        await action.addProfileFormQrCode();
        if (mounted) widget.onClose();
        return;
      }
      final future = BaseNavigator.push<String>(context, const ScanPage());
      widget.onClose();
      final url = await future;
      if (url == null) return;
      await action.addProfileFromLink(url);
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitCustom() {
    final id = ref
        .read(profilesActionProvider.notifier)
        .addCustomProfile('未命名配置');
    final future = openFlvpUpstreamPage(
      context,
      CustomProfileView(profileId: id, isNew: true),
    );
    widget.onClose();
    unawaited(future);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    switch (_kind) {
      case _AddKind.link:
        await _submitLink();
      case _AddKind.file:
        await _submitFile();
      case _AddKind.qr:
        await _submitQrCode();
      case _AddKind.custom:
        _submitCustom();
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    setState(() {
      _url = text;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FlvpThemeScope.colorsOf(context);
    return FlvpModal(
      platform: widget.platform,
      title: '添加配置',
      subtitle: '链接 / 本地文件 / 二维码 / 自定义',
      onClose: _busy ? () {} : widget.onClose,
      footer: [
        FlvpButton(
          variant: FlvpButtonVariant.text,
          label: '取消',
          onPressed: _busy ? null : widget.onClose,
        ),
        FlvpButton(
          label: _actionLabel,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          FlvpSegmented<_AddKind>(
            full: true,
            value: _kind,
            options: const [
              FlvpSegmentedOption(_AddKind.link, '链接'),
              FlvpSegmentedOption(_AddKind.file, '文件'),
              FlvpSegmentedOption(_AddKind.qr, '二维码'),
              FlvpSegmentedOption(_AddKind.custom, '自定义'),
            ],
            onChanged: (value) {
              if (_busy) return;
              setState(() {
                _kind = value;
                _error = null;
              });
            },
          ),
          ..._body(colors),
          if (_error != null)
            Text(_error!, style: flvpText(12, color: colors.warn)),
        ],
      ),
    );
  }

  List<Widget> _body(FlvpColors colors) => switch (_kind) {
    _AddKind.link => [
      FlvpField(
        label: '名称（可选）',
        value: _name,
        placeholder: '留空则使用订阅返回的名称',
        onChanged: (value) {
          if (!_busy) setState(() => _name = value);
        },
      ),
      FlvpField(
        label: '订阅链接',
        value: _url,
        placeholder: 'https:// 或 vless://、ss:// 等分享链接，每行一条',
        mono: true,
        multiline: true,
        onChanged: (value) {
          if (!_busy) {
            setState(() {
              _url = value;
              _error = null;
            });
          }
        },
      ),
      FlvpTileButton(
        icon: 'ClipboardPaste',
        label: '从剪贴板粘贴',
        onTap: () {
          if (!_busy) _paste();
        },
      ),
      Text(
        '支持 Clash 配置链接与分享链接；一次粘贴多条会批量导入，分享链接合并为一份配置。',
        style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
      ),
    ],
    _AddKind.file => [
      Text(
        '选择本机的 Clash 配置（YAML）或分享链接文本，导入后作为本地配置保存。',
        style: flvpText(12.5, weight: FontWeight.w400, color: colors.ink2),
      ),
      Text(
        '文件会先交给内核校验，校验不通过不会写入配置列表。',
        style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
      ),
    ],
    _AddKind.qr => [
      Text(
        _mobile ? '打开相机扫描配置二维码，识别到的链接会直接导入。' : '选择一张包含配置二维码的图片，识别到的链接会直接导入。',
        style: flvpText(12.5, weight: FontWeight.w400, color: colors.ink2),
      ),
      Text(
        _mobile ? '仅识别二维码中的订阅或分享链接。' : '需要在系统里允许应用访问图片文件。',
        style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
      ),
    ],
    _AddKind.custom => [
      Text(
        '创建一个空的自定义配置，随后在完整工作区里添加代理、策略组、规则与 DNS 等分区。',
        style: flvpText(12.5, weight: FontWeight.w400, color: colors.ink2),
      ),
      Text(
        '自定义配置不使用订阅链接，源配置由工作区里的分区生成，可随时查看运行配置。',
        style: flvpText(12, weight: FontWeight.w400, color: colors.ink3),
      ),
    ],
  };
}
