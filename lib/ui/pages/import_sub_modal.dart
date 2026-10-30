import 'package:flutter/material.dart';

import '../store/store_scope.dart';
import '../widgets/controls.dart';
import '../widgets/feedback.dart';

/// components/ImportSubModal.tsx
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
  String _name = '';
  String _url = '';

  bool get _valid =>
      _name.trim().isNotEmpty &&
      RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(_url.trim());

  void _submit() {
    if (!_valid) return;
    FlvpStoreScope.read(context).importSub(_name.trim(), _url.trim());
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) => FlvpModal(
    platform: widget.platform,
    title: '导入订阅',
    subtitle: '支持 Clash、Sing-box 与 V2Ray 订阅链接',
    onClose: widget.onClose,
    footer: [
      FlvpButton(
        variant: FlvpButtonVariant.text,
        label: '取消',
        onPressed: widget.onClose,
      ),
      FlvpButton(label: '导入', onPressed: _valid ? _submit : null),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        FlvpField(
          label: '名称',
          value: _name,
          placeholder: '例如：FLVP 高级订阅',
          onChanged: (value) => setState(() => _name = value),
        ),
        FlvpField(
          label: '订阅链接',
          value: _url,
          placeholder: 'https://',
          mono: true,
          onChanged: (value) => setState(() => _url = value),
        ),
        _PasteButton(
          onTap: () => setState(() {
            _url = 'https://sub.flvp.io/api/v1/client/subscribe?token=4c9e2a';
            if (_name.trim().isEmpty) _name = '新订阅';
          }),
        ),
      ],
    ),
  );
}

class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TonalTileButton(
    icon: 'ClipboardPaste',
    label: '从剪贴板粘贴',
    onTap: onTap,
  );
}

/// `inline-flex h-8 items-center gap-2 rounded-[10px] bg-tile px-3 text-[13px]
/// font-medium text-ink2 hover:text-ink`
class _TonalTileButton extends StatelessWidget {
  const _TonalTileButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FlvpTileButton(
    icon: icon,
    label: label,
    onTap: onTap,
  );
}
